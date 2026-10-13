require "test_helper"

class InvitationMutationTest < ActiveSupport::TestCase
  test "creating an invitation sends mail to its normalized email address" do
    invitation = accounts(:acme).invitations.new(email: " NEW@EXAMPLE.TEST ", role: "agent")

    assert_emails 1 do
      assert_difference "Invitation.count", +1 do
        InvitationMutation.refresh!(invitation)
      end
    end

    assert_equal "new@example.test", invitation.reload.email
    assert_equal ["new@example.test"], ActionMailer::Base.deliveries.sole.to
  end

  test "invalid invitations are neither saved nor emailed" do
    [{email: "invalid", role: "agent"}, {email: "new@example.test", role: "customer"}].each do |attributes|
      invitation = accounts(:acme).invitations.new(attributes)

      assert_no_emails do
        assert_no_difference "Invitation.count" do
          assert_raises(ActiveRecord::RecordInvalid) { InvitationMutation.refresh!(invitation) }
        end
      end
    end
  end
end
