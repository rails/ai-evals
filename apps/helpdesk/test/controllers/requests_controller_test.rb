require "test_helper"

class RequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :customer
  end

  test "customer requests work when the application is mounted under a path prefix" do
    get requests_path, headers: @headers, env: {"SCRIPT_NAME" => "/helpdesk"}

    assert_response :success
    assert_equal "/helpdesk/api/v1/requests", request.path
    assert_equal accounts(:acme).tickets.where(requester: users(:customer)).pluck(:id).sort,
      response.parsed_body.fetch("requests").pluck("id").sort
  end

  test "customers list only their own requests without staff fields" do
    get requests_path, headers: @headers

    assert_response :success
    requests = response.parsed_body["requests"]
    assert_equal users(:customer).id, requests.first["requester_id"]
    assert_equal accounts(:acme).tickets.where(requester: users(:customer)).pluck(:id).sort, requests.pluck("id").sort
    assert_empty requests.first.keys & %w[assignee_id assignee group_id group priority email_reply_token]
  end

  test "customers cannot read or update requests belonging to another customer or account" do
    [tickets(:solved), tickets(:globex)].each do |ticket|
      get request_path(ticket), headers: @headers
      assert_response :not_found

      get comments_request_path(ticket), headers: @headers
      assert_response :not_found

      assert_no_changes -> { ticket.reload.attributes } do
        assert_no_difference "Comment.count" do
          patch request_path(ticket), params: {request: {status: "solved", comment: {body: "Not my request"}}}, headers: @headers, as: :json
        end
      end
      assert_response :not_found
    end
  end

  test "staff cannot use customer request endpoints" do
    [:owner, :agent].each do |user|
      sign_in user

      get requests_path, headers: @headers
      assert_response :forbidden

      get request_path(tickets(:open)), headers: @headers
      assert_response :forbidden

      get comments_request_path(tickets(:open)), headers: @headers
      assert_response :forbidden

      assert_no_changes -> { tickets(:open).reload.attributes } do
        assert_no_difference ["Ticket.count", "Comment.count"] do
          post requests_path, params: {request: {subject: "A staff request", comment: {body: "Please help"}}}, headers: @headers, as: :json
          assert_response :forbidden

          patch request_path(tickets(:open)), params: {request: {status: "solved"}}, headers: @headers, as: :json
          assert_response :forbidden
        end
      end
    end
  end

  test "customers see the request representation without staff fields" do
    tickets(:open).update_columns(
      public_updated_at: Time.utc(2026, 1, 2, 12, 0, 0, 123456),
      updated_at: Time.utc(2026, 1, 3, 12, 0, 0, 654321)
    )

    get request_path(tickets(:open)), headers: @headers

    assert_response :success
    assert_equal ["request"], response.parsed_body.keys
    request = response.parsed_body["request"]
    assert_equal %w[created_at id merged_into_id requester_id status subject updated_at], request.keys.sort
    assert_equal tickets(:open).id, request["id"]
    assert_equal users(:customer).id, request["requester_id"]
    assert_equal "2026-01-01T12:00:00.000000Z", request["created_at"]
    assert_equal "2026-01-02T12:00:00.123456Z", request["updated_at"]
  end

  test "requests can be filtered by status and are ordered by their public timestamps" do
    tickets(:pending).update_columns(updated_at: Time.current)

    get requests_path, params: {status: "pending"}, headers: @headers

    assert_response :success
    assert_equal [tickets(:email).id, tickets(:pending).id], response.parsed_body["requests"].pluck("id")
  end

  test "requests reject staff filters" do
    {assignee_id: users(:owner).id, requester_id: users(:other_customer).id, group_id: groups(:billing).id, priority: "high", q: "receipt"}.each do |filter, value|
      get requests_path, params: {filter => value}, headers: @headers

      assert_response :bad_request
    end
  end

  test "customers create a request with a public opening comment" do
    assert_difference ["Ticket.count", "Comment.count"], 1 do
      post requests_path, params: {request: {subject: "Cannot download invoice", comment: {body: "Please send a copy."}}}, headers: @headers, as: :json
    end

    assert_response :created
    ticket = Ticket.find(response.parsed_body.dig("request", "id"))
    assert_equal accounts(:acme), ticket.account
    assert_equal users(:customer), ticket.requester
    assert_equal "open", ticket.status
    assert_nil ticket.assignee
    assert_equal "Please send a copy.", ticket.comments.sole.body
    assert_equal users(:customer), ticket.comments.sole.author
    assert_equal accounts(:acme), ticket.comments.sole.account
    assert ticket.comments.sole.public
  end

  test "request creation rejects supplied account and requester ids" do
    {account_id: accounts(:globex).id, requester_id: users(:globex_customer).id}.each do |attribute, foreign_id|
      attributes = {subject: "Cannot download invoice", comment: {body: "Please send a copy."}}.merge(attribute => foreign_id)

      assert_no_difference ["Ticket.count", "Comment.count"] do
        post requests_path, params: {request: attributes}, headers: @headers, as: :json
      end

      assert_response :unprocessable_entity
    end
  end

  test "request creation rejects an invalid opening comment without creating a ticket" do
    assert_no_difference ["Ticket.count", "Comment.count"] do
      post requests_path, params: {request: {subject: "Cannot download invoice", comment: {body: ""}}}, headers: @headers, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "customers can solve requests and reopen them by replying" do
    patch request_path(tickets(:open)), params: {request: {status: "solved"}}, headers: @headers, as: :json
    assert_response :success
    assert_equal "solved", tickets(:open).reload.status

    assert_difference -> { tickets(:open).comments.count }, 1 do
      patch request_path(tickets(:open)), params: {request: {comment: {body: "The problem came back."}}}, headers: @headers, as: :json
    end

    assert_response :success
    assert_equal "open", tickets(:open).reload.status
    assert tickets(:open).comments.last.public
    assert_equal ["request"], response.parsed_body.keys
    assert_empty response.parsed_body["request"].keys & %w[assignee_id assignee group_id group priority requester email_reply_token]
  end

  test "customer replies cannot set comment visibility or staff fields" do
    [true, false].each do |visibility|
      assert_no_changes -> { tickets(:open).reload.attributes } do
        assert_no_difference "Comment.count" do
          patch request_path(tickets(:open)), params: {request: {status: "solved", comment: {body: "My reply", public: visibility}}}, headers: @headers, as: :json
        end
      end
      assert_response :unprocessable_entity
    end

    patch request_path(tickets(:open)), params: {request: {status: "solved", assignee_id: users(:agent).id}}, headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal users(:owner), tickets(:open).reload.assignee
    assert_equal "open", tickets(:open).status
  end

  test "request updates require the request envelope" do
    assert_no_changes -> { tickets(:open).reload.attributes } do
      patch request_path(tickets(:open)), params: {ticket: {status: "solved"}}, headers: @headers, as: :json
    end

    assert_response :bad_request
  end

  test "private notes do not change customer-visible content or timestamps" do
    sign_in :owner
    ticket = tickets(:open)
    original_public_time = ticket.public_updated_at
    original_staff_time = ticket.updated_at

    patch ticket_path(ticket), params: {ticket: {comment: {body: "Escalate internally", public: false}}}, headers: @headers, as: :json
    assert_response :success
    assert_operator ticket.reload.updated_at, :>, original_staff_time
    assert_equal original_public_time, ticket.public_updated_at

    sign_in :customer
    get request_path(ticket), headers: @headers
    assert_response :success
    assert_equal original_public_time.iso8601(6), response.parsed_body.dig("request", "updated_at")

    get comments_request_path(ticket), headers: @headers
    assert_response :success
    assert_equal [comments(:opening).id], response.parsed_body["comments"].pluck("id")
  end

  test "customers cannot reopen a merged request" do
    source = tickets(:open)
    source.update!(status: "closed", merged_into: tickets(:pending))

    assert_no_changes -> { source.reload.attributes } do
      assert_no_difference "Comment.count" do
        patch request_path(source), params: {request: {comment: {body: "Please reopen"}}}, headers: @headers, as: :json
      end
    end

    assert_response :unprocessable_entity
  end
end
