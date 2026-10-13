require "test_helper"
require "timeout"

class ConcurrentRequestsTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    sign_in :owner
  end

  teardown do
    # These tables have no fixtures, so reloading fixtures does not clear them.
    Session.delete_all
    EmailToken.delete_all
    InboundReceipt.delete_all
  end

  test "signing in waits for a password change and checks the committed password" do
    user = users(:customer)
    ready = Queue.new
    login = nil

    user.with_lock("FOR NO KEY UPDATE") do
      UserMutation.change_password!(user, current_password: "secret123456", password: "a new password")

      login = Thread.new do
        Thread.current.report_on_exception = false
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << connection.raw_connection.backend_pid
          Session.start!(Account.find(user.account_id), email: user.email, password: "secret123456")
        end
      rescue Session::InvalidCredentials => error
        error
      end

      connection = ActiveRecord::Base.lease_connection
      login_pid = Timeout.timeout(5) { ready.pop }
      holder_pid = connection.raw_connection.backend_pid

      ActiveRecord::Base.uncached do
        Timeout.timeout(5) do
          until connection.select_value("SELECT #{holder_pid} = ANY(pg_blocking_pids(#{login_pid}))")
            flunk "Sign in finished without waiting for the password change" unless login.alive?
            Thread.pass
          end
        end
      end
    end

    assert_instance_of Session::InvalidCredentials, Timeout.timeout(5) { login.value }
    assert_empty user.sessions.reload
  ensure
    login&.kill if login&.alive?
    login&.join
  end

  test "reading account resources does not wait for an account mutation" do
    while_locked(accounts(:acme)) do
      [tickets_path, "/api/v1/tickets/#{tickets(:open).id}", me_path].each do |path|
        get path, headers: @headers

        assert_response :success
      end
    end
  end

  test "editing a ticket does not wait for an unrelated account mutation" do
    ticket = tickets(:open)

    while_locked(accounts(:acme)) do
      patch "/api/v1/tickets/#{ticket.id}", params: {ticket: {priority: "high"}}, headers: @headers, as: :json

      assert_response :success
    end

    assert_equal "high", ticket.reload.priority
  end

  test "editing a ticket does not wait for a different ticket in the same account" do
    ticket = tickets(:open)

    while_locked(tickets(:pending)) do
      patch "/api/v1/tickets/#{ticket.id}", params: {ticket: {priority: "high"}}, headers: @headers, as: :json

      assert_response :success
    end

    assert_equal "high", ticket.reload.priority
  end

  test "replying to a ticket does not wait for an unrelated account mutation" do
    ticket = tickets(:open)

    while_locked(accounts(:acme)) do
      patch "/api/v1/tickets/#{ticket.id}", params: {ticket: {comment: {body: "We are investigating."}}}, headers: @headers, as: :json

      assert_response :success
    end

    assert_equal "We are investigating.", ticket.comments.last.body
  end

  test "an incoming email reply does not wait for an unrelated account mutation" do
    ticket = tickets(:email)

    while_locked(accounts(:acme)) do
      assert_difference ["Comment.count", "InboundReceipt.count"], 1 do
        IncomingSupportEmail.new(reply_to(ticket)).process
      end
    end

    assert_equal "open", ticket.reload.status
    assert_equal "Please keep investigating.", ticket.comments.last.body
  end

  test "an incoming email reply does not wait for a change to the sender's profile" do
    ticket = tickets(:email)

    while_locked(ticket.requester) do
      assert_difference ["Comment.count", "InboundReceipt.count"], 1 do
        IncomingSupportEmail.new(reply_to(ticket)).process
      end
    end

    assert_equal "open", ticket.reload.status
    assert_equal "Please keep investigating.", ticket.comments.last.body
  end

  test "an existing customer's new email request does not wait for an unrelated account mutation" do
    ticket_ids = users(:customer).account.tickets.ids
    message = reply_to(tickets(:email))
    message.to = "acme@#{Rails.application.config.x.support_domain}"
    message = Mail.new(message.to_s)

    while_locked(accounts(:acme)) do
      assert_no_difference "User.count" do
        assert_difference ["Ticket.count", "Comment.count", "InboundReceipt.count"], 1 do
          IncomingSupportEmail.new(message).process
        end
      end
    end

    ticket = users(:customer).account.tickets.where.not(id: ticket_ids).sole
    assert_equal users(:customer), ticket.requester
    assert_equal "Please keep investigating.", ticket.comments.sole.body
  end

  test "simultaneous copies of one email reply to the same ticket are processed once" do
    ticket = tickets(:email)
    messages = 2.times.map { reply_to(ticket, message_id: "duplicate@example.test") }

    ActiveRecord::Base.uncached do
      assert_difference ["Comment.count", "InboundReceipt.count"], 1 do
        run_concurrently(*messages.map { |message| -> { IncomingSupportEmail.new(message).process } })
      end
    end

    assert_equal "open", ticket.reload.status
    assert_equal "Please keep investigating.", ticket.comments.last.body
  end

  test "simultaneous copies of one email sent to different tickets are processed once" do
    first, second = tickets(:email), tickets(:solved)
    second.update!(email_reply_token: "b" * 48)
    messages = [first, second].map { |ticket| reply_to(ticket, message_id: "duplicate@example.test") }

    ActiveRecord::Base.uncached do
      assert_difference ["Comment.count", "InboundReceipt.count"], 1 do
        run_concurrently(*messages.map { |message| -> { IncomingSupportEmail.new(message).process } })
      end
    end

    assert_equal 1, Comment.where(ticket: [first, second], body: "Please keep investigating.").count
  end

  private

  def reply_to(ticket, message_id: "reply@example.test")
    Mail.new(<<~EMAIL.chomp)
      From: #{ticket.requester.email}
      To: reply+#{ticket.email_reply_token}@#{Rails.application.config.x.support_domain}
      Subject: Re: #{ticket.subject}
      Message-ID: <#{message_id}>
      Content-Type: text/plain; charset=UTF-8

      Please keep investigating.
    EMAIL
  end

  def run_concurrently(*operations)
    ready, start = Queue.new, Queue.new
    workers = operations.map do |operation|
      Thread.new do
        Thread.current.report_on_exception = false
        ready << true
        start.pop
        ActiveRecord::Base.connection_pool.with_connection { operation.call }
      end
    end
    operations.size.times { ready.pop }
    operations.size.times { start << true }
    workers.each(&:value)
  ensure
    operations.size.times { start << true }
    workers&.each(&:join)
  end

  # Committed fixtures let the holder and request use separate connections. The
  # queues establish the lock before the request; PostgreSQL bounds any wait.
  def while_locked(record)
    ready, release = Queue.new, Queue.new
    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        record.class.transaction do
          record.class.lock("FOR NO KEY UPDATE").find(record.id)
          ready << true
          release.pop
        end
      end
    rescue => error
      ready << error
    end

    result = ready.pop
    raise result if result.is_a?(Exception)

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      previous_timeout = connection.select_value("SHOW lock_timeout")
      connection.execute("SET lock_timeout = '250ms'")
      begin
        yield
      ensure
        connection.execute("SET lock_timeout = #{connection.quote(previous_timeout)}")
      end
    end
  ensure
    release << true
    holder&.join
  end
end
