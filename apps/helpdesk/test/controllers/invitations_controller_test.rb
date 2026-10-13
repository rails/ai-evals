require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  test "administrators invite staff and send a link with a seven day lifetime" do
    freeze_time
    sign_in :owner

    %w[admin agent].each do |role|
      assert_emails 1 do
        assert_difference "Invitation.count", +1 do
          post invitations_path, params: {invitation: {email: " #{role.upcase}@EXAMPLE.TEST ", role: role}},
            headers: @headers, as: :json
        end
      end

      assert_response :created
      invitation = accounts(:acme).invitations.find(response.parsed_body.dig("invitation", "id"))
      assert_equal "#{role}@example.test", invitation.email
      assert_equal role, invitation.role
      assert_equal "pending", invitation.status
      assert_equal 7.days.from_now, invitation.expires_at
      assert_equal [invitation.email], ActionMailer::Base.deliveries.last.to
      assert_equal EmailToken.digest(email_token_from), invitation.token_digest
      assert_nil response.parsed_body.fetch("invitation").fetch("accepted_at")
      assert_not response.parsed_body.fetch("invitation").key?("token_digest")
    end
  end

  test "agents and customers cannot manage invitations" do
    [:agent, :customer].each do |user|
      sign_in user

      get invitations_path, headers: @headers
      assert_response :forbidden
      get invitation_path(invitations(:pending)), headers: @headers
      assert_response :forbidden

      assert_no_emails do
        assert_no_difference "Invitation.count" do
          post invitations_path, params: {invitation: {email: "new@example.test", role: "agent"}},
            headers: @headers, as: :json
        end
      end
      assert_response :forbidden

      assert_no_changes -> { invitations(:pending).reload.attributes } do
        post resend_invitation_path(invitations(:pending)), headers: @headers
        assert_response :forbidden
        delete invitation_path(invitations(:pending)), headers: @headers
        assert_response :forbidden
      end
    end
  end

  test "customer roles existing users and already invited emails cannot be invited" do
    sign_in :owner

    [
      ["new@example.test", "customer", :unprocessable_entity],
      [users(:customer).email, "agent", :unprocessable_entity],
      [invitations(:pending).email.upcase, "agent", :conflict]
    ].each do |email, role, status|
      assert_no_emails do
        assert_no_difference "Invitation.count" do
          post invitations_path, params: {invitation: {email: email, role: role}}, headers: @headers, as: :json
        end
      end
      assert_response status
    end
  end

  test "pending invitations reserve their email against customer registration until revoked" do
    registration = {user: {name: "Invitee", email: invitations(:pending).email, password: "secret123456"}}

    assert_no_emails do
      assert_no_difference "User.count" do
        post registrations_path, params: registration, headers: account_headers(:acme), as: :json
      end
    end
    assert_response :unprocessable_entity

    sign_in :owner
    delete invitation_path(invitations(:pending)), headers: @headers
    assert_response :no_content

    assert_difference "User.count", +1 do
      post registrations_path, params: registration, headers: account_headers(:acme), as: :json
    end
    assert_response :created
    assert_equal "customer", response.parsed_body.dig("user", "role")
  end

  test "listing and showing invitations are scoped to the administrator's account" do
    sign_in :owner

    get invitations_path, headers: @headers
    assert_response :ok
    assert_equal [invitations(:pending).id, invitations(:expired).id].sort,
      response.parsed_body.fetch("invitations").pluck("id").sort

    get invitations_path(status: "expired"), headers: @headers
    assert_response :ok
    assert_equal [invitations(:expired).id], response.parsed_body.fetch("invitations").pluck("id")
    assert_equal "expired", response.parsed_body.fetch("invitations").sole["status"]

    get invitation_path(invitations(:globex)), headers: @headers
    assert_response :not_found
  end

  test "public preview shows the intended recipient and business only for the correct tenant" do
    post invitation_previews_path, params: {invitation_preview: {token: "pending-invitation-token"}},
      headers: account_headers(:acme), as: :json

    assert_response :ok
    assert_equal({
      "email" => invitations(:pending).email, "role" => "agent", "business_name" => accounts(:acme).name,
      "subdomain" => accounts(:acme).subdomain, "expires_at" => invitations(:pending).expires_at.utc.iso8601(6)
    }, response.parsed_body.fetch("invitation_preview"))

    post invitation_previews_path, params: {invitation_preview: {token: "pending-invitation-token"}},
      headers: account_headers(:globex), as: :json
    assert_response :bad_request
    assert_equal "InvalidToken", response.parsed_body["error"]
  end

  test "acceptance creates verified staff consumes the invitation and requires no verification email" do
    freeze_time

    assert_difference "User.count", +1 do
      assert_no_emails do
        assert_no_difference ["EmailToken.count", "Session.count"] do
          post invitation_acceptances_path, params: {invitation_acceptance: {
            token: "pending-invitation-token", name: " New Agent ", password: "secret123456"
          }}, headers: account_headers(:acme), as: :json
        end
      end
    end

    assert_response :created
    user = accounts(:acme).users.find(response.parsed_body.dig("user", "id"))
    assert_equal invitations(:pending).email, user.email
    assert_equal "New Agent", user.name
    assert_equal "agent", user.role
    assert user.verified?
    assert user.authenticate("secret123456")
    assert_equal "accepted", invitations(:pending).reload.status
    assert_equal Time.current, invitations(:pending).accepted_at
    assert_nil invitations(:pending).token_digest

    assert_no_difference "User.count" do
      post invitation_acceptances_path, params: {invitation_acceptance: {
        token: "pending-invitation-token", name: "Another Agent", password: "secret123456"
      }}, headers: account_headers(:acme), as: :json
    end
    assert_response :bad_request
    assert_equal "InvalidToken", response.parsed_body["error"]

    sign_in user
    get me_path, headers: @headers
    assert_response :ok
  end

  test "failed acceptance preserves the invitation and does not create a user" do
    assert_no_emails do
      assert_no_difference "User.count" do
        assert_no_changes -> { invitations(:pending).reload.attributes } do
          post invitation_acceptances_path, params: {invitation_acceptance: {
            token: "pending-invitation-token", name: "New Agent", password: "short"
          }}, headers: account_headers(:acme), as: :json
        end
      end
    end

    assert_response :unprocessable_entity
  end

  test "resending replaces the token and invalidates the earlier link" do
    sign_in :owner

    assert_emails 1 do
      assert_no_difference "Invitation.count" do
        post resend_invitation_path(invitations(:pending)), headers: @headers
      end
    end
    assert_response :ok
    replacement_token = email_token_from
    assert_equal EmailToken.digest(replacement_token), invitations(:pending).reload.token_digest

    post invitation_previews_path, params: {invitation_preview: {token: "pending-invitation-token"}},
      headers: account_headers(:acme), as: :json
    assert_response :bad_request

    post invitation_previews_path, params: {invitation_preview: {token: replacement_token}},
      headers: account_headers(:acme), as: :json
    assert_response :ok
  end

  test "expired invitations cannot be previewed or accepted and can be renewed" do
    post invitation_previews_path, params: {invitation_preview: {token: "expired-invitation-token"}},
      headers: account_headers(:acme), as: :json
    assert_response :bad_request

    assert_no_difference "User.count" do
      post invitation_acceptances_path, params: {invitation_acceptance: {
        token: "expired-invitation-token", name: "Late Agent", password: "secret123456"
      }}, headers: account_headers(:acme), as: :json
    end
    assert_response :bad_request

    freeze_time
    sign_in :owner
    assert_emails 1 do
      post resend_invitation_path(invitations(:expired)), headers: @headers
    end
    assert_response :ok
    assert_equal "pending", response.parsed_body.dig("invitation", "status")
    assert_equal 7.days.from_now, invitations(:expired).reload.expires_at

    post invitation_previews_path, params: {invitation_preview: {token: email_token_from}},
      headers: account_headers(:acme), as: :json
    assert_response :ok
  end

  test "revoking an invitation invalidates its link and prevents resend" do
    sign_in :owner

    delete invitation_path(invitations(:pending)), headers: @headers
    assert_response :no_content
    assert_equal "revoked", invitations(:pending).reload.status
    assert_nil invitations(:pending).token_digest

    delete invitation_path(invitations(:pending)), headers: @headers
    assert_response :no_content

    post invitation_previews_path, params: {invitation_preview: {token: "pending-invitation-token"}},
      headers: account_headers(:acme), as: :json
    assert_response :bad_request

    assert_no_emails do
      post resend_invitation_path(invitations(:pending)), headers: @headers
    end
    assert_response :conflict
  end

  test "accepted invitations cannot be resent or revoked" do
    post invitation_acceptances_path, params: {invitation_acceptance: {
      token: "pending-invitation-token", name: "New Agent", password: "secret123456"
    }}, headers: account_headers(:acme), as: :json
    assert_response :created
    sign_in :owner

    assert_no_changes -> { invitations(:pending).reload.attributes } do
      assert_no_emails do
        post resend_invitation_path(invitations(:pending)), headers: @headers
        assert_response :conflict
        delete invitation_path(invitations(:pending)), headers: @headers
        assert_response :conflict
      end
    end
  end
end
