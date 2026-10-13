require "test_helper"

class SupportMailboxTest < ActionMailbox::TestCase
  test "a new sender opens a request and receives a verification link" do
    assert_emails 1 do
      assert_difference ["User.count", "Ticket.count", "Comment.count", "InboundReceipt.count", "EmailToken.count"], 1 do
        receive_inbound_email_from_fixture "customer_email.eml"
      end
    end

    customer = accounts(:acme).users.find_by!(email: "casey@example.test")
    ticket = accounts(:acme).tickets.find_by!(requester: customer)
    assert_equal "Casey Customer", customer.name
    assert_equal "customer", customer.role
    assert_not customer.verified?
    assert_equal "Trouble downloading my invoice", ticket.subject
    assert_equal "open", ticket.status
    assert_match(/\A[a-f0-9]{48}\z/, ticket.email_reply_token)
    assert_equal "Could you send me a copy of my invoice?\n", ticket.comments.sole.body
    assert_equal customer, ticket.comments.sole.author
    assert ticket.comments.sole.public
    assert_equal [customer.email], ActionMailer::Base.deliveries.sole.to
    assert_equal customer.email_tokens.sole.token_digest, EmailToken.digest(email_token_from)
  end

  test "an existing customer keeps their credentials and receives no new verification" do
    customer = users(:customer)
    ticket_ids = Ticket.ids

    assert_no_changes -> { customer.reload.attributes } do
      assert_no_emails do
        assert_no_difference ["User.count", "EmailToken.count"] do
          assert_difference "Ticket.count", 1 do
            receive_support_email from: customer.email
          end
        end
      end
    end

    assert_equal customer, Ticket.where.not(id: ticket_ids).sole.requester
  end

  test "the recipient chooses the account when the sender belongs to several accounts" do
    ticket_ids = accounts(:globex).tickets.ids
    assert_no_difference -> { accounts(:acme).tickets.count } do
      assert_difference -> { accounts(:globex).tickets.count }, 1 do
        receive_support_email from: users(:customer).email, to: "globex@#{Rails.application.config.x.support_domain}"
      end
    end

    assert_equal users(:globex_customer), accounts(:globex).tickets.where.not(id: ticket_ids).sole.requester
  end

  test "a repeated message ID is processed once even when the raw message changes" do
    receive_support_email message_id: "duplicate@example.test"

    assert_no_emails do
      assert_no_difference ["Ticket.count", "Comment.count", "InboundReceipt.count"] do
        receive_support_email message_id: "duplicate@example.test", body: "A retransmitted copy with a different body."
      end
    end
  end

  test "message IDs are deduplicated separately for each account" do
    assert_difference ["Ticket.count", "InboundReceipt.count"], 2 do
      receive_support_email message_id: "shared@example.test"
      receive_support_email message_id: "shared@example.test", to: "globex@#{Rails.application.config.x.support_domain}"
    end
  end

  test "a requester reply reopens an email ticket without creating another ticket" do
    ticket = tickets(:email)

    assert_no_emails do
      assert_no_difference ["Ticket.count", "User.count"] do
        assert_difference ["Comment.count", "InboundReceipt.count"], 1 do
          receive_support_email to: reply_address(ticket), body: "I still need help."
        end
      end
    end

    assert_equal "open", ticket.reload.status
    assert_equal "I still need help.", ticket.comments.last.body
    assert_equal ticket.requester, ticket.comments.last.author
    assert ticket.comments.last.public
  end

  test "a requester can reply when the notification subject exceeds the ticket subject limit" do
    subject = "x" * 200
    receive_support_email subject: subject
    ticket = accounts(:acme).tickets.find_by!(subject: subject)

    assert_emails 1 do
      TicketMutation.update!(ticket, users(:agent),
        {"status" => "pending", "comment" => {"body" => "Please try again."}}, customer: false)
    end
    notification = ActionMailer::Base.deliveries.sole
    reply_subject = "Re: #{notification.subject}"
    assert_operator reply_subject.length, :>, 200

    assert_no_emails do
      assert_no_difference ["Ticket.count", "User.count"] do
        assert_difference ["Comment.count", "InboundReceipt.count"], 1 do
          receive_support_email to: notification.reply_to.sole, subject: reply_subject, body: "It still fails."
        end
      end
    end

    assert_equal "open", ticket.reload.status
    assert_equal subject, ticket.subject
    assert_equal "It still fails.", ticket.comments.last.body
    assert_equal ticket.requester, ticket.comments.last.author
    assert ticket.comments.last.public
  end

  test "an oversized new ticket subject leaves no side effects and allows a corrected retry" do
    sender = "new-customer@example.test"
    message_id = "long-subject@example.test"

    assert_no_emails do
      assert_no_difference ["User.count", "Ticket.count", "Comment.count", "InboundReceipt.count", "EmailToken.count"] do
        receive_support_email from: sender, subject: "x" * 201, message_id: message_id
      end
    end

    assert_emails 1 do
      assert_difference ["User.count", "Ticket.count", "Comment.count", "InboundReceipt.count", "EmailToken.count"], 1 do
        receive_support_email from: sender, subject: "x" * 200, message_id: message_id
      end
    end
  end

  test "knowing a reply address does not let another customer join the conversation" do
    assert_no_changes -> { tickets(:email).reload.attributes } do
      assert_no_emails do
        assert_no_difference ["User.count", "Comment.count", "InboundReceipt.count"] do
          receive_support_email from: users(:other_customer).email, to: reply_address(tickets(:email))
        end
      end
    end
  end

  test "closed tickets ignore email replies" do
    tickets(:email).update!(status: "closed", merged_into: tickets(:open))

    assert_no_emails do
      assert_no_difference ["Comment.count", "InboundReceipt.count"] do
        receive_support_email to: reply_address(tickets(:email))
      end
    end

    assert_equal "closed", tickets(:email).reload.status
  end

  test "staff suspended users and pending invitees cannot create email requests" do
    assert_no_emails do
      assert_no_difference ["User.count", "Ticket.count", "Comment.count", "InboundReceipt.count"] do
        [users(:agent).email, users(:suspended).email, invitations(:pending).email].each do |sender|
          receive_support_email from: sender
        end
      end
    end
  end

  test "automated mail and support-address senders are ignored" do
    assert_no_emails do
      assert_no_difference ["Ticket.count", "User.count", "InboundReceipt.count"] do
        receive_support_email "Auto-Submitted" => "auto-replied"
        receive_support_email "Precedence" => "bulk"
        receive_support_email from: "robot@#{Rails.application.config.x.support_domain}"
      end
    end
  end

  test "unknown recipients and messages addressed to two accounts are ignored" do
    assert_no_difference ["Ticket.count", "InboundReceipt.count"] do
      receive_support_email to: "missing@#{Rails.application.config.x.support_domain}"
      receive_support_email cc: "globex@#{Rails.application.config.x.support_domain}"
    end
  end

  test "support mail can arrive through Cc" do
    ticket_ids = Ticket.ids
    assert_difference "Ticket.count", 1 do
      receive_support_email to: "colleague@example.test", cc: "acme@#{Rails.application.config.x.support_domain}"
    end

    assert_equal accounts(:acme), Ticket.where.not(id: ticket_ids).sole.account
  end

  test "multipart messages use the plain body and ignore attachments" do
    ticket_ids = Ticket.ids
    receive_inbound_email_from_mail from: users(:customer).email, to: "acme@#{Rails.application.config.x.support_domain}", subject: "Invoice" do |mail|
      mail.text_part { |part| part.body "Please send my invoice." }
      mail.html_part { |part| part.body "<p>Please send my invoice.</p>" }
      mail.attachments["private.txt"] = "This attachment must not become a comment."
    end

    assert_equal "Please send my invoice.", Ticket.where.not(id: ticket_ids).sole.comments.sole.body
  end

  test "HTML-only and empty messages do not create requests" do
    assert_no_difference ["Ticket.count", "InboundReceipt.count"] do
      receive_support_email content_type: "text/html", body: "<p>Hello</p>"
      receive_support_email body: "  "
    end
  end

  test "a message without an original Message-ID is ignored" do
    source = file_fixture("customer_email.eml").read.sub(/^Message-ID:.*\n/, "")

    assert_no_emails do
      assert_no_difference ["Ticket.count", "User.count", "InboundReceipt.count"] do
        receive_inbound_email_from_source source
      end
    end
  end

  private

  def receive_support_email(**options)
    receive_inbound_email_from_mail(from: users(:customer).email, to: "acme@#{Rails.application.config.x.support_domain}",
      subject: "A question about my account", body: "Can you help?",
      message_id: "#{SecureRandom.hex(12)}@example.test", **options)
  end

  def reply_address(ticket)
    "reply+#{ticket.email_reply_token}@#{Rails.application.config.x.support_domain}"
  end
end
