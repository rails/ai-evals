require "test_helper"

class AssociationLoadingTest < ActionDispatch::IntegrationTest
  %i[offset cursor].each do |pagination|
    test "ticket association queries stay constant with #{pagination} pagination" do
      sign_in :owner
      records = create_tickets(12).reverse

      assert_constant_association_queries(tickets_path, "tickets", records, pagination: pagination, params: {q: "Preloading ticket"}) do |row, ticket|
        assert_equal ticket.requester.attributes.slice("id", "name", "email"), row.fetch("requester")
        assert_equal ticket.assignee.attributes.slice("id", "name"), row.fetch("assignee")
        assert_equal ticket.group.attributes.slice("id", "name"), row.fetch("group")
      end
    end

    test "staff comment author queries stay constant with #{pagination} pagination" do
      sign_in :owner
      ticket = tickets(:open)
      create_comments(ticket, 12)

      assert_constant_association_queries(comments_ticket_path(ticket), "comments", ticket.comments.to_a, pagination: pagination) do |row, comment|
        assert_equal comment.author.attributes.slice("id", "name"), row.fetch("author")
        assert_equal comment.public, row.fetch("public")
      end
    end

    test "customer comment author queries stay constant with #{pagination} pagination" do
      sign_in :customer
      ticket = tickets(:open)
      create_comments(ticket, 12)
      public_comments = ticket.comments.where(public: true).to_a

      assert_constant_association_queries(comments_request_path(ticket), "comments", public_comments, pagination: pagination) do |row, comment|
        assert_equal comment.author.attributes.slice("id", "name"), row.fetch("author")
        assert row.fetch("public")
      end
    end
  end

  test "group deletion selects replacement defaults without a query per user" do
    sign_in :owner

    counts = [3, 12].map do |size|
      group = accounts(:acme).groups.create!(name: "Default group #{size}")
      replacements = size.times.map do |index|
        user = create_user("Default agent #{size} #{index}", role: "agent")
        accounts(:acme).group_memberships.create!(group: group, user: user, default: true)
        oldest = accounts(:acme).group_memberships.create!(group: groups(:billing), user: user)
        accounts(:acme).group_memberships.create!(group: groups(:support), user: user)
        oldest
      end

      queries = select_queries { delete group_path(group), headers: @headers }

      assert_response :no_content
      assert_not Group.exists?(group.id)
      assert_empty GroupMembership.where(group_id: group.id)
      replacements.each do |membership|
        assert membership.reload.default
        assert_equal [membership.id], membership.user.group_memberships.where(default: true).ids
      end
      queries
    end

    assert_equal counts.first, counts.last, "Default promotion should not look up each user's remaining memberships separately"
  end

  %i[group membership suspension].each do |operation|
    test "#{operation} cleanup does not load associations for each affected ticket" do
      sign_in :owner

      counts = [3, 12].map do |size|
        group = accounts(:acme).groups.create!(name: "Cleanup group #{size}")
        assignee = create_user("Cleanup agent #{size}", role: "agent")
        membership = accounts(:acme).group_memberships.create!(group: group, user: assignee, default: true)
        records = size.times.map do |index|
          accounts(:acme).tickets.create!(
            subject: "Cleanup ticket #{index}", requester: users(:customer), assignee: assignee,
            group: group, public_updated_at: 1.day.ago
          )
        end
        public_times = records.to_h { |ticket| [ticket.id, ticket.public_updated_at] }

        queries = select_queries do
          case operation
          when :group
            delete group_path(group), headers: @headers
          when :membership
            delete group_membership_path(membership), headers: @headers
          when :suspension
            patch user_path(assignee), params: {user: {suspended: true}}, headers: @headers, as: :json
          end
        end

        assert_response((operation == :suspension) ? :success : :no_content)
        records.each do |ticket|
          original_time = ticket.updated_at
          assert_nil ticket.reload.assignee_id
          assert_equal public_times.fetch(ticket.id), ticket.public_updated_at
          assert_operator ticket.updated_at, :>, original_time
          if operation == :group
            assert_nil ticket.group_id
          else
            assert_equal group.id, ticket.group_id
          end
        end
        queries
      end

      assert_equal counts.first, counts.last, "Clearing assignments should not add association reads for each ticket"
    end
  end

  private

  def create_tickets(count)
    count.times.map do |index|
      requester = create_user("Requester #{index}", role: "customer")
      assignee = create_user("Agent #{index}", role: "agent")
      group = accounts(:acme).groups.create!(name: "Preloading group #{index}")
      accounts(:acme).group_memberships.create!(group: group, user: assignee)

      accounts(:acme).tickets.create!(
        subject: "Preloading ticket #{index}", requester: requester, assignee: assignee,
        group: group, public_updated_at: Time.current
      )
    end
  end

  def create_comments(ticket, count)
    count.times do |index|
      author = create_user("Author #{index}", role: "agent")
      ticket.comments.create!(account: ticket.account, author: author, body: "Reply #{index}", public: true)
    end
  end

  def create_user(name, role:)
    accounts(:acme).users.create!(name: name, email: "#{name.parameterize}@example.test",
      password: SessionTestHelper::PASSWORD, role: role, verified: true)
  end

  def assert_constant_association_queries(path, collection, records, pagination:, params: {})
    counts = [3, 12].map do |size|
      page = (pagination == :offset) ? {per_page: size} : {page: {size: size}}
      queries = select_queries do
        get path, params: params.merge(page), headers: @headers
      end

      assert_response :success
      rows = response.parsed_body.fetch(collection)
      expected = records.first(size)
      assert_equal size, rows.size
      assert_equal expected.map(&:id), rows.pluck("id")
      rows.zip(expected).each { |row, record| yield row, record }
      queries
    end

    assert_equal counts.first, counts.last, "Association queries should not grow with the number of rendered records"
  end

  def select_queries
    queries = 0
    counter = ->(*, payload) do
      next if payload[:name] == "SCHEMA"
      if payload[:sql].match?(/\A\s*SELECT\b/i)
        # Cached lookups still represent per-record association access.
        queries += 1
      end
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    queries
  end
end
