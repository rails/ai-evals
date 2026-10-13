require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "public registration creates an unverified customer and sends a verification link" do
    assert_emails 1 do
      assert_difference ["User.count", "EmailToken.count"], +1 do
        post registrations_path, params: {user: {name: "New Customer", email: " NEW@EXAMPLE.TEST ", password: "secret123456"}},
          headers: account_headers(:acme), as: :json
      end
    end

    assert_response :created
    user = accounts(:acme).users.find(response.parsed_body.dig("user", "id"))
    assert_equal "customer", user.role
    assert_equal "new@example.test", user.email
    assert_not user.verified?
    assert_equal [user.email], ActionMailer::Base.deliveries.sole.to
  end

  test "registration rejects duplicate emails without sending another link" do
    assert_no_emails do
      assert_no_difference ["User.count", "EmailToken.count"] do
        post registrations_path, params: {user: {name: "Duplicate", email: users(:customer).email.upcase, password: "secret123456"}},
          headers: account_headers(:acme), as: :json
      end
    end

    assert_response :unprocessable_entity
  end

  test "registration cannot choose a staff role" do
    assert_no_emails do
      assert_no_difference ["User.count", "EmailToken.count"] do
        post registrations_path, params: {user: {name: "New Customer", email: "new@example.test", password: "secret123456", role: "admin"}},
          headers: account_headers(:acme), as: :json
      end
    end

    assert_response :unprocessable_entity
  end
end
