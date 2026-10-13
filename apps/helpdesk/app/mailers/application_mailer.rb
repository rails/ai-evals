class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("HELPDESK_MAIL_FROM", "support@example.test") }
  self.delivery_job = MailDeliveryJob
end
