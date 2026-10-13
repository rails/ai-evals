require "test_helper"

class AccountLifecycleTest < ActionDispatch::IntegrationTest
  test "account creation records its administrator as the owner" do
    post account_create_path, params: {account: {
      name: "New Company", subdomain: "new-company",
      admin: {name: "New Owner", email: "owner@new.example", password: PASSWORD}
    }}, as: :json

    assert_response :created
    account = Account.find(response.parsed_body.dig("account", "id"))
    assert_equal account.users.sole, account.owner
    assert_nil account.cancelled_at

    post "/api/v1/accounts", params: {}, as: :json
    assert_response :not_found
  end

  test "only the designated owner can cancel an account" do
    other_admin = additional_administrator

    [users(:agent), users(:customer), other_admin].each do |user|
      sign_in user

      assert_no_changes -> { accounts(:acme).reload.cancelled_at } do
        assert_no_difference "Session.count" do
          post account_cancel_path, headers: @headers
        end
      end

      assert_response :forbidden
      get account_path, headers: @headers
      assert_response :ok
    end
  end

  test "cancellation revokes every tenant session and preserves business records without changing another tenant" do
    freeze_time do
      owner_token = sign_in(:owner)
      sign_in :owner
      sign_in :agent
      sign_in :customer
      globex_token = sign_in(:globex_owner)
      globex_session_ids = accounts(:globex).sessions.ids
      globex_headers = @headers.dup
      EmailTokenLifecycle.issue!(users(:owner), "recovery")
      EmailTokenLifecycle.issue!(users(:customer), "recovery")
      sign_in :owner
      owner_headers = @headers.dup
      before = business_records

      post account_cancel_path, headers: owner_headers

      assert_response :no_content
      assert_equal Time.current, accounts(:acme).reload.cancelled_at
      assert_empty accounts(:acme).sessions
      assert_equal before, business_records
      assert_equal globex_session_ids, accounts(:globex).sessions.ids
      assert_nil accounts(:globex).reload.cancelled_at

      get account_path, headers: owner_headers.merge("Authorization" => "Bearer #{owner_token}")
      assert_response :unauthorized

      get account_path, headers: globex_headers.merge("Authorization" => "Bearer #{globex_token}")
      assert_response :ok
      get portal_path, headers: account_headers(:globex)
      assert_response :ok
    end
  end

  test "the account header cannot use another tenant owner to cancel or reactivate" do
    sign_in :globex_owner
    wrong_tenant_headers = @headers.merge(account_headers(:acme))

    post account_cancel_path, headers: wrong_tenant_headers
    assert_response :unauthorized
    assert_nil accounts(:acme).reload.cancelled_at

    AccountLifecycle.cancel!(accounts(:acme))
    post account_reactivate_path, headers: wrong_tenant_headers
    assert_response :unauthorized
    assert_not_nil accounts(:acme).reload.cancelled_at
    assert_nil accounts(:globex).reload.cancelled_at
  end

  test "a cancelled account permits only its owner to obtain a recovery session" do
    other_admin = additional_administrator
    AccountLifecycle.cancel!(accounts(:acme))

    [users(:agent), users(:customer), other_admin].each do |user|
      assert_no_difference "Session.count" do
        post sessions_path, params: {session: {email: user.email, password: PASSWORD}},
          headers: account_headers(:acme), as: :json
      end
      assert_response :unauthorized
    end

    sign_in :owner
    get account_path, headers: @headers
    assert_response :ok
    assert_equal accounts(:acme).id, response.parsed_body.dig("account", "id")

    delete session_path, headers: @headers
    assert_response :no_content
    get account_path, headers: @headers
    assert_response :unauthorized
  end

  test "a recovery session cannot read or mutate ordinary helpdesk resources" do
    AccountLifecycle.cancel!(accounts(:acme))
    sign_in :owner
    before = business_records

    [me_path, tickets_path, requests_path, users_path, staff_path, groups_path, invitations_path].each do |path|
      get path, headers: @headers
      assert_response :forbidden
    end
    get portal_path, headers: account_headers(:acme)
    assert_response :not_found

    patch ticket_path(tickets(:open)), params: {ticket: {status: "solved"}}, headers: @headers, as: :json
    assert_response :forbidden
    post requests_path, params: {request: {subject: "Blocked request", comment: {body: "No new work"}}}, headers: @headers, as: :json
    assert_response :forbidden
    assert_equal before, business_records
  end

  test "reactivation preserves helpdesk data and the fresh owner session without resurrecting old sessions" do
    old_owner_headers = session_headers(:owner).dup
    old_agent_headers = session_headers(:agent).dup
    EmailTokenLifecycle.issue!(users(:owner), "recovery")
    AccountLifecycle.cancel!(accounts(:acme))
    before = business_records
    sign_in :owner
    recovery_headers = @headers.dup
    recovery_session_ids = accounts(:acme).sessions.reload.ids

    post account_reactivate_path, headers: recovery_headers

    assert_response :no_content
    assert_nil accounts(:acme).reload.cancelled_at
    assert_equal before, business_records
    assert_equal recovery_session_ids, accounts(:acme).sessions.reload.ids
    get tickets_path, headers: recovery_headers
    assert_response :ok
    get portal_path, headers: account_headers(:acme)
    assert_response :ok
    [old_owner_headers, old_agent_headers].each do |headers|
      get account_path, headers: headers
      assert_response :unauthorized
    end
    sign_in :agent
    get tickets_path, headers: @headers
    assert_response :ok
  end

  test "a cancelled owner can reset a forgotten password and reactivate the account" do
    AccountLifecycle.cancel!(accounts(:acme))

    assert_emails 1 do
      post password_resets_path, params: {password_reset: {email: users(:owner).email}},
        headers: account_headers(:acme), as: :json
    end
    assert_response :accepted
    token = email_token_from
    assert_equal [users(:owner).email], ActionMailer::Base.deliveries.last.to

    post password_resets_confirm_path, params: {password_reset: {token: token, password: "replacement password"}},
      headers: account_headers(:acme), as: :json
    assert_response :no_content
    assert_not_nil accounts(:acme).reload.cancelled_at
    post sessions_path, params: {session: {email: users(:owner).email, password: "replacement password"}},
      headers: account_headers(:acme), as: :json
    assert_response :created
    token = response.parsed_body.dig("session", "token")
    headers = account_headers(:acme).merge("Authorization" => "Bearer #{token}")
    post account_reactivate_path, headers: headers
    assert_response :no_content
    assert_nil accounts(:acme).reload.cancelled_at
  end

  test "reactivation is available immediately before ninety days" do
    freeze_time
    AccountLifecycle.cancel!(accounts(:acme))
    cancellation_time = accounts(:acme).reload.cancelled_at

    travel_to(cancellation_time + 90.days - 1.second) do
      sign_in :owner
      post account_reactivate_path, headers: @headers
      assert_response :no_content
      assert_nil accounts(:acme).reload.cancelled_at
    end
  end

  test "an existing recovery session cannot reactivate an account at ninety days" do
    freeze_time
    AccountLifecycle.cancel!(accounts(:acme))
    cancellation_time = accounts(:acme).reload.cancelled_at
    recovery_headers = nil
    travel_to(cancellation_time + 90.days - 1.second) do
      sign_in :owner
      recovery_headers = @headers.dup
    end

    travel_to(cancellation_time + 90.days) do
      assert_no_changes -> { accounts(:acme).reload.cancelled_at } do
        post account_reactivate_path, headers: recovery_headers
      end
      assert_response :forbidden
      get account_path, headers: recovery_headers
      assert_response :ok
      assert_equal cancellation_time.iso8601(6), response.parsed_body.dig("account", "cancelled_at")
      assert_no_difference "Session.count" do
        post sessions_path, params: {session: {email: users(:owner).email, password: PASSWORD}},
          headers: account_headers(:acme), as: :json
      end
      assert_response :unauthorized
    end
  end

  private

  def additional_administrator
    accounts(:acme).users.create!(name: "Another administrator", email: "another-admin@acme.test",
      password: PASSWORD, role: "admin", verified: true)
  end

  def business_records
    [User, Group, GroupMembership, Invitation, Ticket, Comment, EmailToken].map do |model|
      model.where(account: accounts(:acme)).order(:id).map(&:attributes)
    end
  end
end
