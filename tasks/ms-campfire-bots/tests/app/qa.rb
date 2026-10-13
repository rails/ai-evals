# The e2e verification environment: the app's own production configuration, minus what a
# sandbox does not have. tests/app/prepare copies this file to config/environments/qa.rb, and
# tests/app/cleanup removes it.
#
# The logger and its level stay as production configures them: a production-only log filter is
# a real fix, and the suites read the server's standard output (production logs there).
require_relative "production"

Rails.application.configure do
  # No Resque workers in the sandbox: jobs run in-process, after the request as in production
  config.active_job.queue_adapter = :async

  # No Thruster or other proxy in front: Rails serves the precompiled assets itself
  config.public_file_server.enabled = true

  # Plain HTTP on the test host names
  config.assume_ssl = false
  config.force_ssl = false

  # The suites use their own host names and browser origins
  config.hosts.clear
  config.action_cable.disable_request_forgery_protection = true
end

# App code sees production (Rails.env.production?, Rails.env.local?)
Rails.env = "production"
