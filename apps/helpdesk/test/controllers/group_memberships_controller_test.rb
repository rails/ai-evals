require "test_helper"

class GroupMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :owner
  end

  test "staff filter memberships within their account" do
    sign_in :agent

    get group_memberships_path, params: {group_id: groups(:billing).id, user_id: users(:agent).id}, headers: @headers

    assert_response :success
    assert_equal [group_memberships(:agent_billing).id], response.parsed_body["group_memberships"].pluck("id")
  end

  test "the first group membership automatically becomes the default" do
    users(:suspended).update!(suspended: false)

    assert_difference "GroupMembership.count", 1 do
      post group_memberships_path, params: {group_membership: {user_id: users(:suspended).id, group_id: groups(:support).id, default: false}}, headers: @headers, as: :json
    end

    assert_response :created
    membership = GroupMembership.find(response.parsed_body.dig("group_membership", "id"))
    assert membership.default
    assert_equal accounts(:acme), membership.account
    assert_equal groups(:support), membership.group
    assert_equal users(:suspended), membership.user
  end

  test "making another group the default leaves one default membership" do
    put make_default_group_membership_path(group_memberships(:agent_billing)), headers: @headers

    assert_response :success
    assert group_memberships(:agent_billing).reload.default
    assert_not group_memberships(:agent_support).reload.default
    assert_equal 1, users(:agent).group_memberships.where(default: true).count
    assert_equal groups(:support), tickets(:pending).reload.group
  end

  test "duplicate memberships are rejected without changing the default" do
    assert_no_difference "GroupMembership.count" do
      post group_memberships_path, params: {group_membership: {user_id: users(:agent).id, group_id: groups(:billing).id, default: true}}, headers: @headers, as: :json
    end

    assert_response :unprocessable_entity
    assert group_memberships(:agent_support).reload.default
    assert_not group_memberships(:agent_billing).reload.default
  end

  test "customers cannot be added to a group" do
    assert_no_difference "GroupMembership.count" do
      post group_memberships_path, params: {group_membership: {user_id: users(:customer).id, group_id: groups(:billing).id}}, headers: @headers, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "group memberships cannot cross account boundaries" do
    assert_no_difference "GroupMembership.count" do
      post group_memberships_path, params: {group_membership: {user_id: users(:globex_owner).id, group_id: groups(:billing).id}}, headers: @headers, as: :json
    end

    assert_response :not_found

    delete group_membership_path(group_memberships(:globex_owner_support)), headers: @headers
    assert_response :not_found
    assert GroupMembership.exists?(group_memberships(:globex_owner_support).id)
  end

  test "memberships cannot reference groups from another account" do
    assert_no_changes -> { group_memberships(:owner_billing).reload.attributes } do
      assert_no_difference "GroupMembership.count" do
        post group_memberships_path, params: {group_membership: {user_id: users(:owner).id, group_id: groups(:globex_support).id, default: true}}, headers: @headers, as: :json
      end
    end

    assert_response :not_found
  end

  test "memberships require existing groups and users" do
    {group_id: SecureRandom.uuid_v7, user_id: SecureRandom.uuid_v7}.each do |attribute, missing_id|
      attributes = {user_id: users(:owner).id, group_id: groups(:support).id, default: true}.merge(attribute => missing_id)

      assert_no_changes -> { group_memberships(:owner_billing).reload.attributes } do
        assert_no_difference "GroupMembership.count" do
          post group_memberships_path, params: {group_membership: attributes}, headers: @headers, as: :json
        end
      end

      assert_response :not_found
    end
  end

  test "membership creation rejects a supplied account id" do
    assert_no_difference "GroupMembership.count" do
      post group_memberships_path, params: {group_membership: {user_id: users(:owner).id, group_id: groups(:support).id, account_id: accounts(:globex).id}}, headers: @headers, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "agents cannot change memberships or defaults" do
    sign_in :agent

    assert_no_difference "GroupMembership.count" do
      delete group_membership_path(group_memberships(:agent_support)), headers: @headers
    end
    assert_response :forbidden

    put make_default_group_membership_path(group_memberships(:agent_billing)), headers: @headers
    assert_response :forbidden
    assert group_memberships(:agent_support).reload.default
  end

  test "removing a default membership promotes a remaining group and clears its assignments" do
    public_time = tickets(:pending).public_updated_at

    assert_difference "GroupMembership.count", -1 do
      delete group_membership_path(group_memberships(:agent_support)), headers: @headers
    end

    assert_response :no_content
    assert group_memberships(:agent_billing).reload.default
    assert_equal groups(:support), tickets(:pending).reload.group
    assert_nil tickets(:pending).assignee
    assert_equal public_time, tickets(:pending).public_updated_at
  end
end
