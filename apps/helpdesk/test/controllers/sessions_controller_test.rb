require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "sign in normalizes email and returns a token that is stored only as a digest" do
    freeze_time do
      assert_difference -> { users(:owner).sessions.count }, +1 do
        post sessions_path, params: {session: {email: " #{users(:owner).email.upcase} ", password: "secret123456"}},
          headers: account_headers(:acme), as: :json
      end

      assert_response :created
      session = users(:owner).sessions.sole
      assert_equal "Bearer", response.parsed_body.dig("session", "token_type")
      assert_equal session.token_digest, Digest::SHA256.hexdigest(response.parsed_body.dig("session", "token"))
      assert_equal 7.days.from_now, session.expires_at
      assert_equal users(:owner).id, response.parsed_body.dig("user", "id")
      assert_not response.parsed_body.fetch("user").key?("password_digest")
    end
  end

  test "invalid blank and suspended credentials have the same response" do
    [
      [users(:owner).email, "wrong password"],
      ["missing@example.test", "secret123456"],
      ["", ""],
      [users(:suspended).email, "secret123456"]
    ].each do |email, password|
      assert_no_difference "Session.count" do
        post sessions_path, params: {session: {email: email, password: password}},
          headers: account_headers(:acme), as: :json
      end

      assert_response :unauthorized
      assert_equal({"error" => "Unauthorized", "description" => "Invalid credentials"}, response.parsed_body)
    end
  end

  test "unverified users must verify their email before signing in" do
    assert_no_difference "Session.count" do
      post sessions_path, params: {session: {email: users(:unverified).email, password: "secret123456"}},
        headers: account_headers(:acme), as: :json
    end

    assert_response :forbidden
    assert_equal "EmailNotVerified", response.parsed_body["error"]
  end

  test "the same email signs into the user belonging to the selected tenant" do
    post sessions_path, params: {session: {email: users(:customer).email, password: "secret123456"}},
      headers: account_headers(:globex), as: :json

    assert_response :created
    assert_equal users(:globex_customer).id, response.parsed_body.dig("user", "id")
    assert_equal accounts(:globex).id, response.parsed_body.dig("account", "id")
    assert_empty users(:customer).sessions
  end

  test "sign out revokes only the current session" do
    first_token = sign_in(:owner)
    sign_in :owner

    assert_difference -> { users(:owner).sessions.count }, -1 do
      delete session_path, headers: @headers
    end
    assert_response :no_content

    get me_path, headers: @headers
    assert_response :unauthorized

    get me_path, headers: @headers.merge("Authorization" => "Bearer #{first_token}")
    assert_response :ok
  end

  test "expired sessions cannot authenticate" do
    freeze_time
    sign_in :owner

    travel 7.days do
      get me_path, headers: @headers
      assert_response :unauthorized
    end
  end
end
