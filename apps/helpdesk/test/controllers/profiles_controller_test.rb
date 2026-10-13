require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :customer
  end

  test "show and update the signed in customer's profile" do
    get me_path, headers: @headers
    assert_response :ok
    assert_equal users(:customer).id, response.parsed_body.dig("user", "id")

    assert_changes -> { users(:customer).reload.name }, to: "New Name" do
      patch me_path, params: {user: {name: " New Name "}}, headers: @headers, as: :json
    end
    assert_response :ok
    assert_equal "New Name", response.parsed_body.dig("user", "name")
  end

  test "identity and role fields cannot be changed through the profile" do
    assert_no_changes -> { users(:customer).reload.attributes } do
      patch me_path, params: {user: {name: "Changed", role: "admin", email: "new@example.test", verified: true}},
        headers: @headers, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "changing the password revokes all sessions and recovery links" do
    sign_in :customer
    EmailTokenLifecycle.issue!(users(:customer), "recovery")

    assert_difference -> { users(:customer).sessions.count }, -2 do
      assert_difference -> { users(:customer).email_tokens.where(purpose: "recovery").count }, -1 do
        put me_password_path, params: {password_change: {current_password: "secret123456", password: "a new password"}},
          headers: @headers, as: :json
      end
    end

    assert_response :no_content
    assert users(:customer).reload.authenticate("a new password")
    assert_not users(:customer).authenticate("secret123456")

    get me_path, headers: @headers
    assert_response :unauthorized
  end

  test "a wrong current password leaves credentials and sessions unchanged" do
    assert_no_changes -> { users(:customer).reload.password_digest } do
      assert_no_difference "Session.count" do
        put me_password_path, params: {password_change: {current_password: "wrong", password: "a new password"}},
          headers: @headers, as: :json
      end
    end

    assert_response :unprocessable_entity
  end

  test "nil and empty replacement passwords leave credentials sessions and recovery links unchanged" do
    user = users(:customer)
    EmailTokenLifecycle.issue!(user, "recovery")
    recovery_token = user.email_tokens.sole

    [nil, ""].each do |password|
      assert_no_changes -> { [user.reload.password_digest, user.sessions.order(:id).ids, recovery_token.reload.attributes] } do
        put me_password_path, params: {password_change: {current_password: "secret123456", password: password}},
          headers: @headers, as: :json
      end

      assert_response :bad_request
    end
  end
end
