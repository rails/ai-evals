class HelpdeskRelayController < ActionMailbox::Ingresses::Relay::InboundEmailsController
  def create
    source = request.body.read
    incoming = ActionMailbox::InboundEmail.create_and_extract_message_id!(source)
    unless incoming
      # Action Mailbox deduplicates identical raw messages. A previously rejected
      # message must still be retryable after, for example, an invitation expires.
      # Successful business processing has its own durable, transactional receipt.
      existing = ActionMailbox::InboundEmail.find_by(message_checksum: OpenSSL::Digest::SHA1.hexdigest(source))
      existing&.route_later
    end
    head :no_content
  end

  private

  def ingress_name = :relay
  def password = ENV["RAILS_INBOUND_EMAIL_PASSWORD"]
end
