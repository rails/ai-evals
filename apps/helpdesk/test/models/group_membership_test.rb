require "test_helper"

class GroupMembershipTest < ActiveSupport::TestCase
  test "memberships must specify whether they are the default" do
    membership = group_memberships(:agent_billing)
    membership.default = nil

    assert_not membership.valid?
    assert membership.errors.of_kind?(:default, :inclusion)

    membership.default = false
    assert membership.valid?
  end

  test "new members must be active staff" do
    membership = accounts(:acme).group_memberships.new(group: groups(:support), user: users(:customer))
    assert_not membership.valid?
    assert_includes membership.errors[:user], "must be an active staff member"

    membership.user = users(:suspended)
    assert_not membership.valid?
    assert_includes membership.errors[:user], "must be an active staff member"
  end

  test "new members must have verified their email address" do
    users(:unverified).update!(role: "agent")
    membership = accounts(:acme).group_memberships.new(group: groups(:support), user: users(:unverified))

    assert_not membership.valid?
    assert_includes membership.errors[:user], "must be an active staff member"
  end

  test "a user can belong to a group only once" do
    duplicate = group_memberships(:agent_billing).dup

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:user_id, :taken)
  end

  test "existing memberships can change defaults after a staff member is suspended" do
    users(:agent).update!(suspended: true)

    GroupMutation.make_default!(group_memberships(:agent_billing))

    assert group_memberships(:agent_billing).reload.default
    assert_not group_memberships(:agent_support).reload.default
  end

  test "duplicate memberships leave the current default unchanged" do
    assert_no_changes -> { group_memberships(:agent_support).reload.attributes } do
      assert_no_difference "GroupMembership.count" do
        assert_raises(ActiveRecord::RecordInvalid) do
          GroupMutation.create_membership!(accounts(:acme),
            "user_id" => users(:agent).id, "group_id" => groups(:billing).id, "default" => true)
        end
      end
    end
  end
end
