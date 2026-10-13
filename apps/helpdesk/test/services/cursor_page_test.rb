require "test_helper"

class CursorPageTest < ActiveSupport::TestCase
  test "accepts nested cursor parameters parsed by Rails" do
    %w[page%5Bsize%5D=1 page%5Bsize%5D=100&page%5Bafter%5D=token page%5Bsize%5D=2&page%5Bbefore%5D=token].each do |query|
      assert_nothing_raised { CursorPage.validate!(request_for("/api/v1/groups?#{query}").query_parameters) }
    end
  end

  test "leaves legacy pagination to the collection controller" do
    [{}, {"page" => "2", "per_page" => "10"}].each do |query|
      assert_nothing_raised { CursorPage.validate!(query) }
    end
  end

  test "rejects invalid page shapes" do
    [nil, 2, [], ["2"]].each do |page|
      assert_invalid({"page" => page})
    end
  end

  test "requires a scalar size between one and one hundred" do
    [nil, "", "0", "01", "101", "1.5", "1x", [], {"value" => "1"}].each do |size|
      assert_invalid({"page" => {"size" => size}})
    end
    assert_invalid({"page" => {"after" => "token"}})
  end

  test "requires nonempty scalar cursors" do
    %w[after before].each do |direction|
      [nil, "", [], {"value" => "token"}].each do |cursor|
        assert_invalid({"page" => {"size" => "2", direction => cursor}})
      end
    end
  end

  test "rejects conflicting pagination options and unknown nested keys" do
    assert_invalid({"page" => {"size" => "2"}, "per_page" => "2"})
    assert_invalid({"page" => {"size" => "2", "after" => "a", "before" => "b"}})
    assert_invalid({"page" => {"size" => "2", "offset" => "10"}})
  end

  test "next and previous links preserve filters and can be followed" do
    account = accounts(:acme)
    actor = users(:owner)
    account.groups.create!(name: "Sales")
    groups = account.groups.order(:id).to_a
    filters = {"query" => "Sales & support + billing"}
    first = page_for(account, actor, "/api/v1/groups?#{filters.merge("page" => {"size" => "1"}).to_query}")

    assert_equal [groups.first.id], first.fetch(:groups)
    assert_nil first.dig(:links, :prev)
    following = first.dig(:links, :next)
    query = request_for(following).query_parameters
    assert_equal filters["query"], query["query"]
    assert_equal({"size" => "1", "after" => first.dig(:meta, :after_cursor)}, query["page"])

    second = page_for(account, actor, following)
    assert_equal [groups.second.id], second.fetch(:groups)
    previous = second.dig(:links, :prev)
    assert_equal({"size" => "1", "before" => second.dig(:meta, :before_cursor)}, request_for(previous).query_parameters["page"])
    assert_equal [groups.first.id], page_for(account, actor, previous).fetch(:groups)
  end

  test "cursors cannot be reused in another account" do
    first = page_for(accounts(:acme), users(:owner), "/api/v1/groups?page[size]=1")

    error = assert_raises(ApiError) do
      page_for(accounts(:globex), users(:globex_owner), first.dig(:links, :next))
    end

    assert_equal 400, error.status
  end

  test "cursors cannot be reused by another user in the same account" do
    first = page_for(accounts(:acme), users(:owner), "/api/v1/groups?page[size]=1")

    error = assert_raises(ApiError) do
      page_for(accounts(:acme), users(:agent), first.dig(:links, :next))
    end

    assert_equal 400, error.status
  end

  test "cursors cannot be reused for another endpoint" do
    first = page_for(accounts(:acme), users(:owner), "/api/v1/groups?page[size]=1")
    user_path = first.dig(:links, :next).sub("/groups?", "/users?")

    error = assert_raises(ApiError) do
      page_for(accounts(:acme), users(:owner), user_path, scope: accounts(:acme).users, key: :users)
    end

    assert_equal 400, error.status
  end

  test "cursors cannot be reused with different filters" do
    account, actor = accounts(:acme), users(:owner)
    first = page_for(account, actor, "/api/v1/users?role=customer&page[size]=1",
      scope: account.users.where(role: "customer"), key: :users)
    query = request_for(first.dig(:links, :next)).query_parameters.merge("role" => "agent")

    error = assert_raises(ApiError) do
      page_for(account, actor, "/api/v1/users?#{query.to_query}",
        scope: account.users.where(role: "agent"), key: :users)
    end

    assert_equal 400, error.status
  end

  test "page size and query parameter order may change while following a cursor" do
    account, actor = accounts(:acme), users(:owner)
    scope = account.users.where(role: "customer", suspended: false)
    first = page_for(account, actor, "/api/v1/users?suspended=false&role=customer&page[size]=1",
      scope: scope, key: :users)
    query = request_for(first.dig(:links, :next)).query_parameters
    query["page"]["size"] = "2"

    following = page_for(account, actor, "/api/v1/users?#{query.to_query}", scope: scope, key: :users)

    assert_equal scope.order(:id).offset(1).pluck(:id), following.fetch(:users)
    assert_equal 2, following.fetch(:users).size
    assert_not following.dig(:meta, :has_more)
    assert_nil following.dig(:links, :next)
  end

  test "tampered cursors are rejected" do
    first = page_for(accounts(:acme), users(:owner), "/api/v1/groups?page[size]=1")
    query = request_for(first.dig(:links, :next)).query_parameters
    cursor = query["page"]["after"]
    cursor[0] = cursor.start_with?("A") ? "B" : "A"

    error = assert_raises(ApiError) do
      page_for(accounts(:acme), users(:owner), "/api/v1/groups?#{query.to_query}")
    end

    assert_equal 400, error.status
  end

  test "ascending pagination continues after a deleted boundary record" do
    account, actor = accounts(:acme), users(:owner)
    scope = account.group_memberships
    memberships = scope.order(:id).to_a
    first = page_for(account, actor, "/api/v1/group_memberships?page[size]=1", scope: scope, key: :group_memberships)
    assert_equal [memberships.first.id], first.fetch(:group_memberships)

    memberships.first.destroy!
    following = page_for(account, actor, first.dig(:links, :next), scope: scope, key: :group_memberships)

    assert_equal [memberships.second.id], following.fetch(:group_memberships)
    assert_nil following.dig(:links, :prev)
    assert following.dig(:meta, :has_more)
  end

  test "backward pagination also works after its boundary record is deleted" do
    account, actor = accounts(:acme), users(:owner)
    scope = account.group_memberships
    first = page_for(account, actor, "/api/v1/group_memberships?page[size]=1", scope: scope, key: :group_memberships)
    second = page_for(account, actor, first.dig(:links, :next), scope: scope, key: :group_memberships)
    third = page_for(account, actor, second.dig(:links, :next), scope: scope, key: :group_memberships)

    scope.find(third.fetch(:group_memberships).sole).destroy!
    previous = page_for(account, actor, third.dig(:links, :prev), scope: scope, key: :group_memberships)

    assert_equal second.fetch(:group_memberships), previous.fetch(:group_memberships)
    assert_nil previous.dig(:links, :next)
  end

  test "ticket pagination orders equal timestamps by descending id in both directions" do
    account, actor = accounts(:acme), users(:owner)
    account.tickets.update_all(updated_at: Time.utc(2026, 2, 1))
    scope = account.tickets
    ordered_ids = scope.order(id: :desc).pluck(:id)

    first = page_for(account, actor, "/api/v1/tickets?page[size]=2", scope: scope, key: :tickets, clock: :updated_at)
    following = page_for(account, actor, first.dig(:links, :next), scope: scope, key: :tickets, clock: :updated_at)
    previous = page_for(account, actor, following.dig(:links, :prev), scope: scope, key: :tickets, clock: :updated_at)

    assert_equal ordered_ids.first(2), first.fetch(:tickets)
    assert_equal ordered_ids.last(2), following.fetch(:tickets)
    assert_equal first.fetch(:tickets), previous.fetch(:tickets)
    assert_nil following.dig(:links, :next)
    assert_nil previous.dig(:links, :prev)
  end

  test "ticket pagination continues after a deleted timestamp boundary" do
    account, actor = accounts(:acme), users(:owner)
    first = page_for(account, actor, "/api/v1/tickets?page[size]=1", scope: account.tickets, key: :tickets, clock: :updated_at)
    boundary = tickets(:email)
    assert_equal [boundary.id], first.fetch(:tickets)

    boundary.comments.destroy_all
    boundary.destroy!
    following = page_for(account, actor, first.dig(:links, :next), scope: account.tickets, key: :tickets, clock: :updated_at)

    assert_equal [tickets(:solved).id], following.fetch(:tickets)
    assert_nil following.dig(:links, :prev)
  end

  test "ticket pagination uses the saved position when the boundary timestamp changes" do
    account, actor = accounts(:acme), users(:owner)
    first = page_for(account, actor, "/api/v1/tickets?page[size]=1", scope: account.tickets, key: :tickets, clock: :updated_at)
    assert_equal [tickets(:email).id], first.fetch(:tickets)

    tickets(:email).update!(updated_at: tickets(:open).updated_at - 1.day)
    following = page_for(account, actor, first.dig(:links, :next), scope: account.tickets, key: :tickets, clock: :updated_at)

    assert_equal [tickets(:solved).id], following.fetch(:tickets)
  end

  private

  def assert_invalid(query)
    error = assert_raises(ApiError) { CursorPage.validate!(query) }
    assert_equal 400, error.status
  end

  def request_for(path)
    ActionDispatch::Request.new(Rack::MockRequest.env_for(path))
  end

  def page_for(account, actor, path, scope: account.groups, key: :groups, clock: nil)
    request = request_for(path)
    CursorPage.validate!(request.query_parameters)
    records, metadata = CursorPage.new(scope, request: request, account: account, actor: actor, clock: clock).page
    metadata.merge(key => records.map(&:id))
  end
end
