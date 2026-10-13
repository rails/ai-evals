require "test_helper"

class EmailTokenRequestTest < ActiveSupport::TestCase
  test "email link requests normalize the address without requiring an existing user" do
    request = EmailTokenRequest.new(email: " NEW@EXAMPLE.TEST ")

    assert request.valid?
    assert_equal "new@example.test", request.email
    assert_not User.exists?(email: request.email)
  end

  test "email link requests reject malformed and overlong addresses" do
    [nil, "", "not-an-email", "two@@example.test", "has space@example.test", "a" * 243 + "@example.test"].each do |email|
      request = EmailTokenRequest.new(email: email)

      assert_not request.valid?
      assert request.errors.added?(:email, :invalid)
    end
  end
end
