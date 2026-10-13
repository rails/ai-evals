class TicketMailer < ApplicationMailer
  def reply(ticket, body)
    @body = body
    domain = Rails.application.config.x.support_domain
    mail to: ticket.requester.email,
      subject: "#{ticket.account.name}: #{ticket.subject}",
      reply_to: "reply+#{ticket.email_reply_token}@#{domain}",
      message_id: "#{SecureRandom.hex(24)}@#{domain}"
  end
end
