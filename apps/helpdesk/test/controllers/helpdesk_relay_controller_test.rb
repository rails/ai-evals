require "test_helper"

class HelpdeskRelayControllerTest < ActionDispatch::IntegrationTest
  setup do
    @source = file_fixture("customer_email.eml").read
    @headers = {
      "Content-Type" => "message/rfc822",
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("actionmailbox", ENV.fetch("RAILS_INBOUND_EMAIL_PASSWORD"))
    }
  end

  test "the authenticated relay routes a message through Action Mailbox" do
    assert_difference ["ActionMailbox::InboundEmail.count", "Ticket.count"], 1 do
      post rails_action_mailbox_relay_inbound_emails_path, params: @source, headers: @headers
    end

    assert_response :no_content
    assert ActionMailbox::InboundEmail.last.delivered?
    assert_equal @source, ActionMailbox::InboundEmail.last.raw_email.download
  end

  test "the relay requires credentials and an RFC 822 content type" do
    assert_no_difference ["ActionMailbox::InboundEmail.count", "Ticket.count"] do
      post rails_action_mailbox_relay_inbound_emails_path, params: @source, headers: @headers.except("Authorization")
      assert_response :unauthorized

      post rails_action_mailbox_relay_inbound_emails_path, params: @source, headers: @headers.merge("Content-Type" => "text/plain")
      assert_response :unsupported_media_type
    end
  end

  test "retrying an identical message does not duplicate the request" do
    post rails_action_mailbox_relay_inbound_emails_path, params: @source, headers: @headers
    assert_response :no_content

    assert_no_emails do
      assert_no_difference ["ActionMailbox::InboundEmail.count", "Ticket.count", "Comment.count", "InboundReceipt.count"] do
        post rails_action_mailbox_relay_inbound_emails_path, params: @source, headers: @headers
      end
    end

    assert_response :no_content
  end

  test "malformed address headers are ignored and do not block a corrected retry" do
    malformed_sources = [
      @source.sub(/^From:.*$/, "From: <>"),
      @source.sub(/^To:.*$/, "To: <>"),
      "Cc: <>\n#{@source}",
      @source.sub(/^To:.*$/, "To: acme@support.example.test, <>")
    ]

    assert_no_emails do
      assert_no_difference ["User.count", "Ticket.count", "Comment.count", "InboundReceipt.count", "EmailToken.count"] do
        malformed_sources.each do |source|
          assert_difference "ActionMailbox::InboundEmail.count", 1 do
            post rails_action_mailbox_relay_inbound_emails_path, params: source, headers: @headers
          end

          assert_response :no_content
          assert ActionMailbox::InboundEmail.last.delivered?
        end
      end
    end

    assert_emails 1 do
      assert_difference ["User.count", "Ticket.count", "Comment.count", "InboundReceipt.count", "EmailToken.count"], 1 do
        post rails_action_mailbox_relay_inbound_emails_path, params: @source, headers: @headers
      end
    end

    assert_response :no_content
    assert ActionMailbox::InboundEmail.last.delivered?
  end

  test "a rejected message can be retried after its sender's invitation expires" do
    @source = @source.sub("casey@example.test", invitations(:pending).email)

    assert_no_difference ["Ticket.count", "InboundReceipt.count"] do
      post rails_action_mailbox_relay_inbound_emails_path, params: @source, headers: @headers
    end
    assert_response :no_content

    invitations(:pending).update!(expires_at: 1.minute.ago)

    assert_no_difference "ActionMailbox::InboundEmail.count" do
      assert_difference ["Ticket.count", "InboundReceipt.count"], 1 do
        post rails_action_mailbox_relay_inbound_emails_path, params: @source, headers: @headers
      end
    end
    assert_response :no_content
  end
end
