require "test_helper"

class GroupTest < ActiveSupport::TestCase
  test "names are stripped before saving" do
    groups(:billing).update!(name: "  Billing team\n")

    assert_equal "Billing team", groups(:billing).reload.name
  end

  test "names must be present and no longer than 100 characters" do
    group = groups(:billing)
    group.name = " \n "
    assert_not group.valid?
    assert group.errors.of_kind?(:name, :blank)

    group.name = "a" * 100
    assert group.valid?

    group.name += "a"
    assert_not group.valid?
    assert group.errors.of_kind?(:name, :too_long)
  end

  test "normalized names are unique without regard to case within each account" do
    group = accounts(:acme).groups.new(name: "  BILLING  ")

    assert_not group.valid?
    assert group.errors.of_kind?(:name, :taken)

    group.account = accounts(:globex)
    assert group.valid?
  end
end
