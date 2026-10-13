# frozen_string_literal: true

# Step 5: flood control and automatic suspension of misbehaving bots.
class BotSuspensionTest < E2E::Test
  def setup
    super
    @hook = E2E::Receiver.url
    # The administrator owns these bots: members are limited to a few
    as(E2E::ADMIN) do
      @bot = unique("Chatty Bot")
      @code = create_bot(@bot, webhook_url: @hook)
      @room_id = create_closed_room(unique("Builds"), members: [ @bot ])
    end
  end

  test "a bot may post 10 messages in 10 seconds" do
    10.times { |index| assert_equal 201, bot_post(@room_id, @code, "Build #{index} passed").code.to_i }
  end

  test "the 11th message is refused with Retry-After until the cooldown ends" do
    10.times { |index| bot_post(@room_id, @code, "Build #{index} passed") }

    rejection = bot_post(@room_id, @code, "One too many")
    assert_equal 429, rejection.code.to_i
    assert_includes 1..30, rejection["Retry-After"].to_i

    sleep 31
    assert_equal 201, bot_post(@room_id, @code, "Back again").code.to_i
  end

  test "five more attempts during the cooldown suspend the bot" do
    10.times { |index| bot_post(@room_id, @code, "Build #{index} passed") }
    assert_equal 429, bot_post(@room_id, @code, "One too many").code.to_i
    4.times { assert_equal 429, bot_post(@room_id, @code, "Still here").code.to_i }
    bot_post(@room_id, @code, "And again")

    assert_equal 403, bot_post(@room_id, @code, "Am I suspended?").code.to_i

    as(E2E::ADMIN) do
      visit "/bots"
      within(bot_entry(@bot)) { assert_text "Suspended" }
    end
  end

  test "webhook replies count towards the limit and are dropped during the cooldown" do
    E2E::Receiver.reply_sequence(@hook, { status: 200, body: "Reply one", content_type: "text/plain" },
                                        { status: 200, body: "Reply two", content_type: "text/plain" })
    9.times { |index| bot_post(@room_id, @code, "Build #{index} passed") }

    as(E2E::ADMIN) do
      post_message @room_id, "status?", mention: @bot
      find_in_room(@room_id, "Reply one")
    end

    assert_equal 429, bot_post(@room_id, @code, "One too many").code.to_i

    as(E2E::ADMIN) do
      post_message @room_id, "status again?", mention: @bot
      assert eventually { webhook_events(@hook, "mention").size >= 2 }
      sleep 2
      visit "/rooms/#{@room_id}"
      assert_no_text "Reply two"
    end
  end

  test "ten failed webhook deliveries in a row suspend the bot" do
    E2E::Receiver.reply(@hook, status: 500)

    as(E2E::ADMIN) do
      9.times { |index| post_message @room_id, "ping #{index}", mention: @bot }
      assert eventually(timeout: 60) { webhook_events(@hook, "mention").size >= 9 }
      assert_equal 201, bot_post(@room_id, @code, "Still alive").code.to_i

      post_message @room_id, "ping 10", mention: @bot
      assert eventually(timeout: 60) { bot_post(@room_id, @code, "Am I suspended?").code.to_i == 403 }, "the bot wasn't suspended"
    end
  end

  test "a successful delivery resets the failure count" do
    as(E2E::ADMIN) do
      E2E::Receiver.reply(@hook, status: 500)
      9.times { |index| post_message @room_id, "ping #{index}", mention: @bot }
      assert eventually(timeout: 60) { webhook_events(@hook, "mention").size >= 9 }

      E2E::Receiver.reply(@hook, status: 204)
      post_message @room_id, "ok?", mention: @bot
      assert eventually(timeout: 60) { webhook_events(@hook, "mention").size >= 10 }

      E2E::Receiver.reply(@hook, status: 500)
      9.times { |index| post_message @room_id, "ping again #{index}", mention: @bot }
      assert eventually(timeout: 60) { webhook_events(@hook, "mention").size >= 19 }
    end

    assert_equal 201, bot_post(@room_id, @code, "Still alive").code.to_i
  end

  test "a suspended bot keeps its rooms and messages but receives no webhooks" do
    assert_equal 201, bot_post(@room_id, @code, "Before the flood").code.to_i

    # Suspended bots drop out of the mention autocomplete: mention it while it's active,
    # send the message once it's suspended
    as(E2E::ADMIN) { compose_message @room_id, "hello?", mention: @bot }
    suspend_by_flooding
    delivered = E2E::Receiver.requests(@hook).size
    as(E2E::ADMIN) { send_composed_message "hello?" }
    sleep 3

    as(E2E::ADMIN) do
      visit "/rooms/#{@room_id}"
      assert_selector ".message", text: "Before the flood"
    end
    assert_equal delivered, E2E::Receiver.requests(@hook).size
  end

  test "only administrators can reactivate a suspended bot" do
    as(E2E::MEMBER) do
      remove_all_bots
      @bot = unique("Member's Bot")
      @code = create_bot(@bot)
    end
    as(E2E::ADMIN) { add_to_closed_room(@room_id, @bot) }
    suspend_by_flooding
    sleep 31 # let the cooldown run out: reactivation is about the suspension

    as(E2E::MEMBER) do
      visit "/bots"
      within(bot_entry(@bot)) { assert_text "Suspended" }
      assert_no_button "Reactivate"
    end
    assert_equal 403, bot_post(@room_id, @code, "Let me in").code.to_i

    as(E2E::ADMIN) do
      visit "/bots"
      within(bot_entry(@bot)) { accept_confirm { click_on "Reactivate" } }
      assert_current_path "/bots"
    end
    assert eventually { bot_post(@room_id, @code, "I'm back").code.to_i == 201 }
  end

  private
    def suspend_by_flooding
      10.times { bot_post(@room_id, @code, "Spam") }
      6.times { bot_post(@room_id, @code, "More spam") }
      assert_equal 403, bot_post(@room_id, @code, "Suspended?").code.to_i
    end

    # The bot's list entry: the element that holds its name, its one "Bot code" field and its buttons
    def bot_entry(name)
      field = all(:field, "Bot code", readonly: true).find do |candidate|
        candidate.find(:xpath, "ancestor::*[contains(normalize-space(.), #{xpath_literal(name)})][1]").all(:field, "Bot code", readonly: true).size == 1
      rescue Capybara::ElementNotFound
        false
      end
      # The whole list item: its buttons may sit beside the element that holds the name and the code
      item = "ancestor::*[self::li or self::tr or @role='listitem' or @role='row'][contains(normalize-space(.), #{xpath_literal(name)})][1]"
      return field.find(:xpath, item) if field.has_xpath?(item, wait: 0)

      # Plain <div> cards: the largest element that still holds only this bot's "Bot code" field.
      # Ancestors come outermost first.
      field.all(:xpath, "ancestor::*[contains(normalize-space(.), #{xpath_literal(name)})]", wait: 0).find do |ancestor|
        ancestor.all(:field, "Bot code", readonly: true, wait: 0).size == 1
      end
    end
end
