require "tmpdir"
require "fileutils"
require "uri"

module MailTestHelper
  extend ActiveSupport::Concern
  include ActionMailer::TestHelper
  include ActionMailer::TestCase::ClearTestDeliveries

  included do
    setup do
      @mail_directory = Dir.mktmpdir("helpdesk-test-mail-")
      @previous_support_domain = Rails.application.config.x.support_domain
      Rails.application.config.x.support_domain = "support.example.test"
      @previous_storage_root = ActiveStorage::Blob.service.root
      ActiveStorage::Blob.service.root = File.join(@mail_directory, "storage")
    end

    teardown do
      Rails.application.config.x.support_domain = @previous_support_domain
      ActiveStorage::Blob.service.root = @previous_storage_root if @previous_storage_root
      FileUtils.remove_entry(@mail_directory) if @mail_directory
    end
  end

  def email_token_from(message = ActionMailer::Base.deliveries.last)
    url = URI.extract(message.body.decoded, %w[http https]).first
    URI.decode_www_form(URI(url).query).to_h.fetch("token")
  end
end
