require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  test "email addresses are normalized" do
    invitation = accounts(:acme).invitations.new(email: " NEW@EXAMPLE.TEST ", role: "agent")

    assert_equal "new@example.test", invitation.email
  end

  test "invalid email addresses and customer roles cannot be invited" do
    [
      {email: "invalid", role: "agent"},
      {email: "@example.test", role: "agent"},
      {email: "name@example@test", role: "agent"},
      {email: "name@localhost", role: "agent"},
      {email: "name with spaces@example.test", role: "agent"},
      {email: "a" * 250 + "@e.co", role: "agent"},
      {email: "new@example.test", role: "customer"}
    ].each do |attributes|
      invitation = accounts(:acme).invitations.new(attributes)

      assert_not invitation.valid?, "Expected invalid invitation attributes: #{attributes.inspect}"
    end
  end

  test "invalid changes do not replace a pending invitation's recipient or role" do
    invitation = invitations(:pending)
    original = invitation.attributes

    [{email: "invalid"}, {role: "customer"}].each do |attributes|
      assert_not invitation.update(attributes)
      assert invitation.errors[attributes.keys.sole].any?
      assert_equal original, invitation.reload.attributes
    end
  end
end
