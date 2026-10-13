# frozen_string_literal: true

require_relative "../test_helper"

class CoreMembershipsTest < HelpdeskTest
  def test_admin_can_create_rename_and_delete_a_group
    owner = sign_up
    group = create_group(owner, "Billing")
    id = record_id(group)
    other = create_group(owner, "Alpha Support")
    assert_equal "Billing", group["name"]
    assert_equal [id, record_id(other)].sort, record_ids(get_collection("/groups", "groups", context: owner))
    renamed = response_field(json_request(:patch, "/groups/#{id}", {
      group: { name: "Accounts" }
    }, context: owner), "group", type: Hash)
    assert_equal "Accounts", renamed["name"]
    assert_equal "Accounts", response_field(json_request(:get, "/groups/#{id}", context: owner), "group", type: Hash)["name"]
    assert_status(204, request(:delete, "/groups/#{id}", context: owner))
    assert_equal [record_id(other)], record_ids(get_collection("/groups", "groups", context: owner))
  end

  def test_admin_can_add_and_remove_an_agent_membership
    owner = sign_up
    agent = add_staff(owner)
    group = create_group(owner, "Technical Support")
    membership = create_membership(owner, group, agent)
    id = record_id(membership)
    other = create_membership(owner, group, owner)
    assert_equal record_id(group), membership["group_id"]
    assert_equal record_id(agent[:user]), membership["user_id"]
    assert_equal id, record_id(response_field(json_request(:get, "/group_memberships/#{id}", context: agent), "group_membership", type: Hash))
    assert_includes record_ids(get_collection("/groups", "groups", context: agent)), record_id(group)
    assert_equal [id, record_id(other)].sort,
      record_ids(get_collection("/group_memberships", "group_memberships", context: agent))
    assert_status(204, request(:delete, "/group_memberships/#{id}", context: owner))
    assert_equal [record_id(other)], record_ids(get_collection("/group_memberships", "group_memberships", context: owner))
  end

  def test_staff_can_route_and_filter_tickets_by_group
    owner = sign_up
    agent = add_staff(owner)
    customer = register_customer(owner)
    group = create_group(owner, "Billing")
    create_membership(owner, group, owner)
    id = record_id(create_request(customer))
    ungrouped_id = record_id(create_request(customer))
    update_ticket(owner, ungrouped_id, group_id: nil, assignee_id: nil)
    routed = update_ticket(owner, id,
      group_id: record_id(group), assignee_id: record_id(owner[:user]))
    assert_equal record_id(group), routed["group_id"]
    assert_equal "Billing", response_field(routed, "group", type: Hash)["name"]
    # Group membership does not restrict staff access to tickets.
    assert_equal record_id(owner[:user]), ticket(agent, id)["assignee_id"]
    assert_equal [id], record_ids(get_collection("/tickets?group_id=#{record_id(group)}", "tickets", context: agent))
    assert_equal [ungrouped_id], record_ids(get_collection("/tickets?group_id=unassigned", "tickets", context: owner))
    # Routing must preserve the requester's access. The instructions do not
    # prohibit including group metadata in customer responses.
    assert_equal id, record_id(customer_request(customer, id))
    cleared = update_ticket(agent, id, group_id: nil, assignee_id: nil)
    assert_nil cleared["group_id"]
    assert_nil cleared["assignee_id"]
  end

  def test_agents_can_read_all_groups_and_memberships_but_only_admins_can_mutate_them
    owner = sign_up
    agent = add_staff(owner)
    customer = register_customer(owner)
    group = gm_create_group(owner)
    member = gm_create_membership(owner, group, owner)
    missing_group = missing_record_id(group)
    missing_member = missing_record_id(member)
    reads = ["/groups", "/groups/#{group['id']}", "/group_memberships", "/group_memberships/#{member['id']}"]
    reads.each { |path| json_request(:get, path, context: agent) }
    (reads + ["/groups/#{missing_group}", "/group_memberships/#{missing_member}"]).each do |path|
      assert_api_error(403, :get, path, context: customer)
    end
    mutations = [
      [:post, "/groups", { group: { name: "Forbidden new group" } }],
      [:post, "/group_memberships", { group_membership: { group_id: group["id"], user_id: agent[:user]["id"] } }]
    ]
    [group["id"], missing_group].each do |id|
      mutations << [:patch, "/groups/#{id}", { group: { name: "Forbidden rename" } }]
      mutations << [:delete, "/groups/#{id}", nil]
    end
    [member["id"], missing_member].each do |id|
      mutations << [:delete, "/group_memberships/#{id}", nil]
      mutations << [:put, "/group_memberships/#{id}/make_default", nil]
    end
    [agent, customer].each do |caller|
      mutations.each { |method, path, body| assert_api_error(403, method, path, body, context: caller) }
    end
    assert_equal [group["id"]], record_ids(get_collection("/groups", "groups", context: owner))
    assert_equal group["name"], gm_group(owner, group["id"])["name"]
    assert_equal [member["id"]], record_ids(get_collection("/group_memberships", "group_memberships", context: owner))
    assert_equal member.values_at("group_id", "user_id", "default"),
      gm_membership(owner, member["id"]).values_at("group_id", "user_id", "default")
  end

  def test_defaults_are_per_user_and_can_be_switched
    owner = sign_up
    agent = add_staff(owner)
    groups = 3.times.map { gm_create_group(owner) }
    first = gm_create_membership(owner, groups[0], owner)
    second = gm_create_membership(owner, groups[1], owner)
    agent_member = gm_create_membership(owner, groups[0], agent)
    assert_equal true, first["default"]
    assert_equal false, second["default"]
    third = gm_create_membership(owner, groups[2], owner, default: true)
    demoted = gm_membership(owner, first["id"])
    assert_equal false, demoted["default"]
    assert_equal true, third["default"]
    promoted = gm_make_default(owner, second)
    assert_equal true, promoted["default"]
    assert_equal false, gm_membership(owner, third["id"])["default"]
    assert_equal true, gm_membership(owner, agent_member["id"])["default"]
    memberships = get_collection("/group_memberships?user_id=#{owner[:user]['id']}", "group_memberships", context: owner)
    assert_equal [second["id"]], memberships.select { |member| member["default"] == true }.map { |member| member["id"] }
    id = create_request(register_customer(owner))["id"]
    update_ticket(owner, id, group_id: nil, assignee_id: nil)
    assigned = update_ticket(owner, id, assignee_id: owner[:user]["id"])
    assert_equal [groups[1]["id"], owner[:user]["id"]], assigned.values_at("group_id", "assignee_id")
  end

  def test_group_and_membership_lists_return_all_records_and_combine_filters
    owner = sign_up
    agent = add_staff(owner)
    groups = %w[Zulu Alpha Middle].map { |name| gm_create_group(owner, name) }
    one = gm_create_membership(owner, groups[2], agent)
    two = gm_create_membership(owner, groups[0], owner)
    three = gm_create_membership(owner, groups[2], owner)
    four = gm_create_membership(owner, groups[1], agent)
    assert_equal record_ids(groups), record_ids(get_collection("/groups", "groups", context: agent))
    assert_equal record_ids([one, two, three, four]), record_ids(get_collection("/group_memberships", "group_memberships", context: agent))
    assert_equal record_ids([one, three]), record_ids(get_collection("/group_memberships?group_id=#{groups[2]['id']}", "group_memberships", context: owner))
    assert_equal record_ids([one, four]), record_ids(get_collection("/group_memberships?user_id=#{agent[:user]['id']}", "group_memberships", context: owner))
    assert_equal [three["id"]], record_ids(get_collection("/group_memberships?group_id=#{groups[2]['id']}&user_id=#{owner[:user]['id']}", "group_memberships", context: owner))
    assert_empty get_collection("/group_memberships?group_id=#{groups[0]['id']}&user_id=#{agent[:user]['id']}", "group_memberships", context: owner)
  end

  private

  def create_group(owner, name)
    response_field(json_request(:post, "/groups", { group: { name: name } },
      context: owner, status: 201), "group", type: Hash)
  end

  def create_membership(owner, group, person)
    response_field(json_request(:post, "/group_memberships", {
      group_membership: { group_id: record_id(group), user_id: record_id(person[:user]) }
    }, context: owner, status: 201), "group_membership", type: Hash)
  end
end
