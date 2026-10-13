require "test_helper"

class GroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :owner
  end

  test "staff can list groups in their account" do
    sign_in :agent

    get groups_path, headers: @headers

    assert_response :success
    assert_equal [groups(:billing).id, groups(:support).id].sort, response.parsed_body["groups"].pluck("id").sort
  end

  test "offset pages include group fields and pagination metadata" do
    group = accounts(:acme).groups.order(:id).first

    get groups_path, params: {page: 1, per_page: 1}, headers: @headers

    assert_response :success
    assert_equal({
      "groups" => [{"id" => group.id, "name" => group.name,
                    "created_at" => group.created_at.utc.iso8601(6), "updated_at" => group.updated_at.utc.iso8601(6)}],
      "count" => 2, "page" => 1, "per_page" => 1, "next_page" => 2, "previous_page" => nil
    }, response.parsed_body)
  end

  test "cursor pages include arrays metadata and navigation links through an empty page" do
    group_ids = accounts(:acme).groups.order(:id).pluck(:id)

    get groups_path, params: {page: {size: 1}}, headers: @headers

    assert_response :success
    first_page = response.parsed_body
    assert_equal %w[groups links meta], first_page.keys.sort
    assert_equal [group_ids.first], first_page["groups"].pluck("id")
    assert_equal true, first_page.dig("meta", "has_more")
    assert_equal %w[after_cursor before_cursor has_more], first_page["meta"].keys.sort
    assert first_page.dig("meta", "after_cursor").present?
    assert first_page.dig("meta", "before_cursor").present?
    assert_nil first_page.dig("links", "prev")
    assert first_page.dig("links", "next").start_with?("#{groups_path}?")

    get first_page.dig("links", "next"), headers: @headers

    assert_response :success
    last_page = response.parsed_body
    assert_equal [group_ids.last], last_page["groups"].pluck("id")
    assert_equal false, last_page.dig("meta", "has_more")
    assert_nil last_page.dig("links", "next")
    assert last_page.dig("links", "prev").start_with?("#{groups_path}?")

    get groups_path, params: {page: {size: 1, after: last_page.dig("meta", "after_cursor")}}, headers: @headers

    assert_response :success
    assert_equal({
      "groups" => [],
      "meta" => {"has_more" => false, "after_cursor" => nil, "before_cursor" => nil},
      "links" => {"next" => nil, "prev" => nil}
    }, response.parsed_body)
  end

  test "administrators create and rename a group" do
    assert_difference "Group.count", 1 do
      post groups_path, params: {group: {name: "Escalations"}}, headers: @headers, as: :json
    end

    assert_response :created
    group = Group.find(response.parsed_body.dig("group", "id"))
    assert_equal accounts(:acme), group.account

    patch group_path(group), params: {group: {name: "Technical escalations"}}, headers: @headers, as: :json
    assert_response :success
    assert_equal "Technical escalations", group.reload.name
  end

  test "agents cannot create or delete groups" do
    sign_in :agent

    assert_no_difference "Group.count" do
      post groups_path, params: {group: {name: "Escalations"}}, headers: @headers, as: :json
    end
    assert_response :forbidden

    assert_no_difference "Group.count" do
      delete group_path(groups(:billing)), headers: @headers
    end
    assert_response :forbidden
  end

  test "customers cannot browse groups" do
    sign_in :customer

    get groups_path, headers: @headers

    assert_response :forbidden
  end

  test "groups in another account cannot be read or deleted" do
    get group_path(groups(:globex_support)), headers: @headers
    assert_response :not_found

    assert_no_difference "Group.count" do
      delete group_path(groups(:globex_support)), headers: @headers
    end
    assert_response :not_found
  end

  test "deleting a group removes memberships and assignments and promotes another default" do
    public_time = tickets(:pending).public_updated_at
    original_time = tickets(:pending).updated_at

    assert_difference ["Group.count", "GroupMembership.count"], -1 do
      delete group_path(groups(:support)), headers: @headers
    end

    assert_response :no_content
    assert_nil tickets(:pending).reload.group
    assert_nil tickets(:pending).assignee
    assert_equal public_time, tickets(:pending).public_updated_at
    assert_operator tickets(:pending).updated_at, :>, original_time
    assert group_memberships(:agent_billing).reload.default
    assert_equal groups(:billing), tickets(:open).reload.group
    assert_equal users(:owner), tickets(:open).assignee
  end
end
