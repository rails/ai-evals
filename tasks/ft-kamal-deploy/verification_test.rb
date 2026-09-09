require "test_helper"
require "kamal"

class VerifierTest < ActiveSupport::TestCase
  test "boots and builds assets with only a secret key" do
    key_only = { "SECRET_KEY_BASE" => SecureRandom.hex(64) }
    assert_equal "production", production_rails("puts Rails.env", env: key_only).strip

    output, status = Open3.capture2e({ "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1" },
      "bin/rails", "assets:precompile", chdir: Rails.root.to_s)
    assert status.success?, output
  end

  test "Kamal accepts the deployment" do
    assert_not_empty config.service
    assert_not_empty config.image
    assert config.registry.server.present? || config.registry.username.present?, "no registry to push the image to"
    assert_predicate config.primary_host, :present?
    assert_equal dockerfile.scan(/^EXPOSE\s+(\d+)/).flatten.last.to_i, config.proxy.app_port
  end

  test "the proxy serves the hostname over SSL and mail links point there" do
    assert_predicate config.proxy, :ssl?
    assert_predicate config.proxy.hosts.first, :present?
    assert_equal({ "host" => config.proxy.hosts.first, "protocol" => "https" },
      settings["mail_url_options"].slice("host", "protocol"))
  end

  test "databases and uploads live on a volume" do
    volumes = config.volume_args.each_slice(2).map { |_, spec| spec.split(":")[1] }
    assert_not_empty volumes

    workdir = dockerfile[/^WORKDIR\s+(\S+)/, 1]
    data = [ *settings["databases"], settings["storage_root"] ].map do |path|
      Pathname.new(path).absolute? ? path.sub(Rails.root.to_s, workdir) : File.join(workdir, path)
    end
    homeless = data.reject { |path| volumes.any? { |volume| path.start_with?("#{volume}/") } }
    assert_empty homeless, "not on a volume (volumes: #{volumes.join(', ')})"
  end

  test "mail goes through the deployer's SMTP server" do
    assert_equal "smtp", settings["delivery_method"]

    clear, secret, smtp = config.env.clear.values.map(&:to_s), secrets.values, settings["smtp"]
    assert_includes clear, smtp["address"]
    assert_includes clear + secret, smtp["user_name"]
    assert_includes secret, smtp["password"]
  end

  test "background jobs run on the box" do
    jobs_role = config.roles.any? { |role| role.cmd.to_s.match?(/jobs|solid_queue/) }
    in_puma = deployment_env["SOLID_QUEUE_IN_PUMA"] != "false" &&
      Rails.root.join("config/puma.rb").read.include?("solid_queue")
    assert jobs_role || in_puma, "no role runs the jobs and the web process does not run Solid Queue"
  end

  test "no secret value is in the repo" do
    assert_not_empty config.env.secret_keys
    files = Dir.chdir(Rails.root) { `git ls-files --cached --others --exclude-standard -- .kamal config/deploy.yml` }
    repo = files.split("\n").sum("") { |file| Rails.root.join(file).read }
    leaked = config.env.secret_keys.select { |name| repo.include?(secrets[name]) }
    assert_empty leaked
  end

  test "secrets resolve from the deployer's environment, and to nothing without it" do
    secrets.each { |name, value| assert_predicate value, :present?, name }

    unset = Kamal::Secrets.new(destination: config.destination, secrets_path: config.secrets_path)
    config.env.secret_keys.each do |name|
      assert_predicate unset[name], :blank?, name
    end
  end

  private
    def config
      @@config ||= Kamal::Configuration.create_from(config_file: Rails.root.join("config/deploy.yml"),
        version: "verifier")
    end

    def dockerfile = Rails.root.join("Dockerfile").read

    def secrets
      @@secrets ||= begin
        deployer = config.env.secret_keys.index_with { SecureRandom.hex(16) }
        unless Rails.root.join(config.secrets_path).exist?
          FileUtils.mkdir_p(Rails.root.join(config.secrets_path).dirname)
          File.write(Rails.root.join(config.secrets_path), deployer.keys.map { |name| "#{name}=$#{name}\n" }.join)
        end
        ENV.update(deployer)
        resolved = deployer.keys.index_with { |name| config.secrets[name] }
        deployer.each_key { |name| ENV.delete(name) }
        resolved
      end
    end

    def deployment_env
      config.env.clear.transform_values(&:to_s).merge(secrets)
    end

    def settings
      @@settings ||= JSON.parse(production_rails(<<~RUBY, env: deployment_env))
        puts({
          mail_url_options: ActionMailer::Base.default_url_options,
          delivery_method: ActionMailer::Base.delivery_method,
          smtp: ActionMailer::Base.smtp_settings,
          databases: ActiveRecord::Base.configurations.configs_for(env_name: "production").map(&:database),
          storage_root: ActiveStorage::Blob.service.root
        }.to_json)
      RUBY
    end

    def production_rails(code, env:)
      output, status = Open3.capture2e(env.merge("RAILS_ENV" => "production"),
        "bin/rails", "runner", code, chdir: Rails.root.to_s)
      assert status.success?, output
      output
    end
end
