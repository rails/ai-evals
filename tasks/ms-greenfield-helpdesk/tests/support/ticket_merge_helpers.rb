# frozen_string_literal: true

module HelpdeskTicketMergeHelpers
  private

  def merge_fixture
    owner = sign_up
    customer = register_customer(owner)
    [owner, customer, create_request(customer)["id"], create_request(customer)["id"]]
  end

  def merge_tickets(context, source, target, **notes)
    data = json_request(:post, "/tickets/#{source}/merge", { merge: { target_id: target }.merge(notes) }, context: context)
    %w[source target].each do |key|
      record_id(response_field(data, key, type: Hash))
    end
    data
  end

  def merge_snapshot(owner, customer, *ids)
    { tickets: ids.map { |id| ticket(owner, id) }, requests: ids.map { |id| customer_request(customer, id) },
      comments: ids.map { |id| comments(owner, id) }, visible_comments: ids.map { |id| comments(customer, id, customer: true) },
      mail: mail_count }
  end

  def merge_group(owner)
    group = response_field(json_request(:post, "/groups", { group: { name: unique("Merge group") } }, context: owner, status: 201), "group", type: Hash)
    record_id(group)
    group
  end

  def merge_membership(owner, group, agent)
    membership = response_field(json_request(:post, "/group_memberships", {
      group_membership: { group_id: group["id"], user_id: agent[:user]["id"] }
    }, context: owner, status: 201), "group_membership", type: Hash)
    record_id(membership)
    membership
  end

  def merge_email_ticket(owner, customer)
    before = all_pages("/tickets", "tickets", context: owner).map { |record| record["id"] }
    deliver_email(email_source(from: customer[:user]["email"], to: "#{owner[:account]['subdomain']}@#{ENV.fetch("HELPDESK_SUPPORT_DOMAIN")}"))
    added = all_pages("/tickets", "tickets", context: owner).reject { |record| before.include?(record["id"]) }
    assert_equal 1, added.size
    added.first["id"]
  end

  def merge_reply_address(owner, id)
    before = mail_count
    update_ticket(owner, id, comment: { body: unique("Ordinary email reply"), public: true })
    messages = mail_since(before)
    assert_equal 1, messages.size
    assert_equal 1, Array(messages.first.reply_to).size
    address = messages.first.reply_to.first
    refute_empty address
    address
  end
end
