require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  test "confirming the emailed link verifies the user and consumes it" do
    EmailTokenLifecycle.issue!(users(:unverified), "verification")
    deliver_enqueued_emails
    token = email_token_from

    assert_changes -> { users(:unverified).reload.verified? }, from: false, to: true do
      assert_difference "EmailToken.count", -1 do
        post email_verifications_confirm_path, params: {email_verification: {token: token}},
          headers: account_headers(:acme), as: :json
      end
    end
    assert_response :ok

    post email_verifications_confirm_path, params: {email_verification: {token: token}},
      headers: account_headers(:acme), as: :json
    assert_response :bad_request
    assert_equal "InvalidToken", response.parsed_body["error"]
  end

  test "resending verification replaces the previous link" do
    EmailTokenLifecycle.issue!(users(:unverified), "verification")
    deliver_enqueued_emails
    previous_token = email_token_from

    assert_emails 1 do
      assert_no_difference "EmailToken.count" do
        post email_verifications_path, params: {email_verification: {email: users(:unverified).email}},
          headers: account_headers(:acme), as: :json
      end
    end
    assert_response :accepted
    replacement_token = email_token_from

    post email_verifications_confirm_path, params: {email_verification: {token: previous_token}},
      headers: account_headers(:acme), as: :json
    assert_response :bad_request
    assert_not users(:unverified).reload.verified?

    post email_verifications_confirm_path, params: {email_verification: {token: replacement_token}},
      headers: account_headers(:acme), as: :json
    assert_response :ok
    assert users(:unverified).reload.verified?
  end

  test "verification requests do not reveal missing verified or suspended users" do
    post email_verifications_path, params: {email_verification: {email: users(:unverified).email}},
      headers: account_headers(:acme), as: :json
    assert_response :accepted
    eligible_response = response.parsed_body

    ["missing@example.test", users(:customer).email, users(:suspended).email].each do |email|
      assert_no_emails do
        assert_no_difference "EmailToken.count" do
          post email_verifications_path, params: {email_verification: {email: email}},
            headers: account_headers(:acme), as: :json
        end
      end
      assert_response :accepted
      assert_equal eligible_response, response.parsed_body
    end
  end
end
