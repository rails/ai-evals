class MailDeliveryJob < ActionMailer::MailDeliveryJob
  self.enqueue_after_transaction_commit = true
  self.log_arguments = false
end
