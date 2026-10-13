# frozen_string_literal: true

# Step 2: webhook callbacks when someone mentions a bot, and replies.
class BotWebhooksTest < E2E::Test
  def setup
    super
    sign_in E2E::ADMIN
    @hook = E2E::Receiver.url
    @bot_name = unique("Ops Bot")
    @code = create_bot(@bot_name, webhook_url: @hook)
    @room_id = create_closed_room(unique("Ops"), members: [ @bot_name ])
    @baseline = webhook_events(@hook).size # later steps may announce the room join
  end

  test "mentioning the bot sends exactly one JSON webhook" do
    post_message @room_id, "restart the build please", mention: @bot_name
    assert eventually { mentions.size == 1 }, "expected one mention webhook, got #{mentions.size}"
    assert_match %r{\Aapplication/json}, last_request.headers["content-type"]

    add_to_closed_room(@room_id, "Kevin")
    post_message @room_id, "nothing to see here"
    post_message @room_id, "can you look?", mention: "Kevin"
    sleep 2
    assert_equal 1, mentions.size, "only mentions of the bot trigger its webhook"
  end

  test "the payload describes the author, the room and the message" do
    post_message @room_id, "restart the build please", mention: @bot_name
    assert eventually { mentions.any? }
    payload = mentions.last

    assert_equal "mention", payload["event"]
    assert_equal "David", payload.dig("author", "name")
    assert_kind_of Integer, payload.dig("author", "id")

    assert_equal @room_id, payload.dig("room", "id")
    assert_kind_of String, payload.dig("room", "name")
    assert_equal "/rooms/#{@room_id}/#{@code}/messages", payload.dig("room", "reply_to")

    message_id = payload.dig("message", "id")
    assert_kind_of Integer, message_id
    # Edges are ignored here: the browser saves the space after a mention as a no-break space (see edge_cases.rb)
    assert_equal "restart the build please", payload.dig("message", "body", "text").to_s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
    assert_includes payload.dig("message", "body", "html"), "restart the build please"
    assert_equal "/rooms/#{@room_id}/@#{message_id}", payload.dig("message", "link")

    # reply_to is the bot's own posting URL and works as is, without a session
    assert_equal 201, http_post(payload.dig("room", "reply_to"), "On it!", "Content-Type" => "text/plain").code.to_i
    visit "/rooms/#{@room_id}"
    assert_includes find(".message", text: "On it!").text, @bot_name
  end

  test "a text or HTML reply is posted into the room as the bot" do
    E2E::Receiver.reply(@hook, status: 200, body: "Restarting build #42", content_type: "text/plain")
    post_message @room_id, "restart the build please", mention: @bot_name

    reply = find_in_room(@room_id, "Restarting build #42")
    assert_includes reply.text, @bot_name

    E2E::Receiver.reply(@hook, status: 200, body: "<strong>Done</strong> in 3s", content_type: "text/html")
    post_message @room_id, "status?", mention: @bot_name

    find_in_room(@room_id, "Done", selector: ".message strong")
  end

  test "a 204 reply posts nothing" do
    E2E::Receiver.reply(@hook, status: 204)
    post_message @room_id, "are you there?", mention: @bot_name
    assert eventually { mentions.any? }
    sleep 2

    visit "/rooms/#{@room_id}"
    assert_selector ".message", count: 1 # only the person's own message
  end

  test "a slow webhook never slows down the person posting" do
    E2E::Receiver.reply(@hook, status: 200, body: "Finally!", content_type: "text/plain", delay: 6)

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    post_message @room_id, "are you there?", mention: @bot_name
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    assert_operator elapsed, :<, 5, "posting took #{elapsed.round(1)}s while the webhook was slow"
    assert eventually(timeout: 20) { mentions.any? }
  end

  test "mentioning a bot without a webhook URL posts normally" do
    quiet_bot = unique("Quiet Bot")
    create_bot(quiet_bot)
    add_to_closed_room(@room_id, quiet_bot)
    baseline = E2E::Receiver.requests(@hook).size

    post_message @room_id, "hello?", mention: quiet_bot
    sleep 2
    assert_equal baseline, E2E::Receiver.requests(@hook).size
  end

  private
    def mentions = webhook_events(@hook, "mention")
    def last_request = E2E::Receiver.requests(@hook).last
end
