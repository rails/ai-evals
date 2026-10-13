require "test_helper"

class ParameterTypesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :owner
  end

  test "signup converts scalar attributes to text and numeric passwords work at login" do
    assert_emails 1 do
      assert_difference ["Account.count", "User.count"], +1 do
        post account_create_path, params: {account: {
          name: 123, subdomain: 456,
          admin: {name: 789, email: "owner@new-company.test", password: 123456789012}
        }}, as: :json
      end
    end

    assert_response :created
    account = Account.find(response.parsed_body.dig("account", "id"))
    owner = account.users.sole
    assert_equal "123", account.name
    assert_equal "456", account.subdomain
    assert_equal "789", owner.name
    assert owner.authenticate("123456789012")

    post email_verifications_confirm_path, params: {email_verification: {token: email_token_from}},
      headers: account_headers(account), as: :json
    assert_response :ok

    assert_difference -> { owner.sessions.count }, +1 do
      post sessions_path, params: {session: {email: owner.email, password: 123456789012}},
        headers: account_headers(account), as: :json
    end
    assert_response :created
    assert_equal owner.id, response.parsed_body.dig("user", "id")
  end

  test "profile updates convert boolean names to text" do
    assert_changes -> { users(:owner).reload.name }, to: "false" do
      patch me_path, params: {user: {name: false}}, headers: @headers, as: :json
    end

    assert_response :ok
    assert_equal "false", response.parsed_body.dig("user", "name")
  end

  test "requests convert numeric subjects and boolean comment bodies to text" do
    sign_in :customer

    assert_difference ["Ticket.count", "Comment.count"], +1 do
      post requests_path, params: {request: {subject: 123, comment: {body: false}}}, headers: @headers, as: :json
    end

    assert_response :created
    ticket = accounts(:acme).tickets.find(response.parsed_body.dig("request", "id"))
    assert_equal "123", ticket.subject
    assert_equal "false", ticket.comments.sole.body
  end

  test "staff replies convert numeric bodies while preserving boolean visibility" do
    assert_difference -> { tickets(:open).comments.count }, +1 do
      patch "/api/v1/tickets/#{tickets(:open).id}", params: {ticket: {comment: {body: 123, public: false}}},
        headers: @headers, as: :json
    end

    assert_response :ok
    comment = tickets(:open).comments.last
    assert_equal "123", comment.body
    assert_not comment.public?
  end

  test "nil signup attributes become blank and roll back the entire account" do
    assert_no_emails do
      assert_no_difference ["Account.count", "User.count", "EmailToken.count"] do
        post account_create_path, params: {account: {
          name: "New Company", subdomain: "new-company",
          admin: {name: nil, email: "owner@new-company.test", password: 123456789012}
        }}, as: :json
      end
    end

    assert_response :unprocessable_entity
  end

  test "nil comment bodies become blank and cannot partially update tickets" do
    assert_no_changes -> { tickets(:open).reload.attributes } do
      assert_no_emails do
        assert_no_difference "Comment.count" do
          patch "/api/v1/tickets/#{tickets(:open).id}", params: {ticket: {status: "solved", comment: {body: nil}}},
            headers: @headers, as: :json
        end
      end
    end

    assert_response :unprocessable_entity
  end

  test "nil and numeric login identifiers receive generic invalid credentials" do
    [nil, 123].each do |email|
      assert_no_difference "Session.count" do
        post sessions_path, params: {session: {email: email, password: nil}}, headers: account_headers, as: :json
      end

      assert_response :unauthorized
      assert_equal({"error" => "Unauthorized", "description" => "Invalid credentials"}, response.parsed_body)
    end
  end

  test "objects and arrays cannot be converted into profile names" do
    [[], {}, ["Changed"], {text: "Changed"}].each do |name|
      assert_no_changes -> { users(:owner).reload.attributes } do
        patch me_path, params: {user: {name: name}}, headers: @headers, as: :json
      end

      assert_response :bad_request
    end
  end

  test "comment visibility still requires a JSON boolean" do
    assert_no_changes -> { tickets(:open).reload.attributes } do
      assert_no_emails do
        assert_no_difference "Comment.count" do
          patch "/api/v1/tickets/#{tickets(:open).id}", params: {ticket: {status: "solved", comment: {body: "Internal note", public: "false"}}},
            headers: @headers, as: :json
        end
      end
    end

    assert_response :unprocessable_entity
  end

  test "assignment IDs require UUID strings" do
    [123, "123", "not-a-uuid", "#{users(:agent).id}0", true].each do |id|
      assert_no_changes -> { tickets(:solved).reload.attributes } do
        patch "/api/v1/tickets/#{tickets(:solved).id}", params: {ticket: {assignee_id: id}}, headers: @headers, as: :json
      end

      assert_response :unprocessable_entity
    end
  end

  test "UUID paths assignments and filters accept uppercase and return canonical IDs" do
    ticket = tickets(:solved)
    agent = users(:agent)

    get "/api/v1/tickets/#{ticket.id.upcase}", headers: @headers
    assert_response :ok
    assert_equal ticket.id, response.parsed_body.dig("ticket", "id")

    patch "/api/v1/tickets/#{ticket.id.upcase}", params: {ticket: {assignee_id: agent.id.upcase}}, headers: @headers, as: :json
    assert_response :ok
    assert_equal agent, ticket.reload.assignee
    assert_equal agent.id, response.parsed_body.dig("ticket", "assignee_id")
    assert_equal agent.id, response.parsed_body.dig("ticket", "assignee", "id")

    get tickets_path, params: {assignee_id: agent.id.upcase}, headers: @headers
    assert_response :ok
    assert_equal accounts(:acme).tickets.where(assignee: agent).pluck(:id).sort,
      response.parsed_body.fetch("tickets").pluck("id").sort
    assert response.parsed_body.fetch("tickets").all? { |row| row.fetch("assignee_id") == agent.id }
  end

  test "membership defaults and suspension flags require JSON booleans" do
    assert_no_difference "GroupMembership.count" do
      post group_memberships_path, params: {group_membership: {
        group_id: groups(:support).id, user_id: users(:owner).id, default: "false"
      }}, headers: @headers, as: :json
    end
    assert_response :unprocessable_entity

    assert_no_changes -> { users(:agent).reload.attributes } do
      patch "/api/v1/users/#{users(:agent).id}", params: {user: {suspended: "true"}}, headers: @headers, as: :json
    end
    assert_response :unprocessable_entity
  end

  test "invalid email links are rejected before checking replacement credentials" do
    post password_resets_confirm_path, params: {password_reset: {token: "invalid", password: 123}}, headers: account_headers, as: :json
    assert_response :bad_request
    assert_equal "InvalidToken", response.parsed_body["error"]

    post invitation_acceptances_path, params: {invitation_acceptance: {token: "invalid", name: "Agent", password: 123}}, headers: account_headers, as: :json
    assert_response :bad_request
    assert_equal "InvalidToken", response.parsed_body["error"]
  end
end
