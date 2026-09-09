require "application_system_test_case"

class VerifierTest < ApplicationSystemTestCase
  setup do
    @card = cards(:logo)
    @comment = comments(:logo_agreement_jz)
    sign_in_as users(:kevin)
    visit card_url(@card)
  end

  test "a reaction shows in the strip with who left it" do
    react "🎉"

    assert_includes reaction("🎉").ancestor(".reaction").native.attribute("outerHTML"), users(:kevin).name.split.first
  end

  test "confirming puts the reaction in the strip and brings the button back, empty" do
    react "💯"

    within comment do
      assert_no_selector ".reaction__input"
      find(".reactions__trigger").click
      assert_equal "", find(".reaction__input").value
    end
  end

  test "people can take back their own reaction, and only their own" do
    react "🔥"

    Capybara.using_session(:jz) do
      sign_in_as users(:jz)
      visit card_url(@card)
      reaction("🔥").click
      assert_no_selector ".reaction__delete"
    end

    reaction("🔥").click
    comment.find(".reaction__delete").click
    assert_no_text "🔥"
  end

  test "a reaction reaches everyone watching the card" do
    wait_for_cable_subscriptions

    Capybara.using_session(:david) do
      sign_in_as users(:david)
      visit card_url(@card)
      react "✨"
    end
    perform_enqueued_jobs

    assert_text "✨", wait: 5
  end

  test "the person reacting does not get their reaction twice" do
    wait_for_cable_subscriptions
    Capybara.using_session(:david) do
      sign_in_as users(:david)
      visit card_url(@card)
      wait_for_cable_subscriptions
    end

    react "🚨"
    perform_enqueued_jobs

    Capybara.using_session(:david) { assert_text "🚨", wait: 5 }
    assert_selector :xpath, "//*[#{shows("🚨")}][not(ancestor-or-self::form)]", count: 1
  end

  test "someone else's reaction landing does not wipe what this viewer is typing" do
    wait_for_cable_subscriptions
    page.execute_script 'addEventListener("turbo:morph", () => document.body.dataset.morphed = true, { once: true })'
    within comment do
      find(".reactions__trigger").click
      find(".reaction__input").set "🤔"
    end

    Capybara.using_session(:david) do
      sign_in_as users(:david)
      visit card_url(@card)
      react "🔥"
    end
    perform_enqueued_jobs

    assert_text "🔥", wait: 5
    page.has_selector?("body[data-morphed]", wait: 3)
    assert_equal "🤔", comment.find(".reaction__input").value
  end

  private
    def comment = find("##{dom_id(@comment)}")

    def shows(content) = "text()[normalize-space(.)='#{content}']"

    def reaction(content)
      comment.find(:xpath, ".//*[#{shows(content)}][not(ancestor-or-self::form)]")
    end

    def react(content)
      within comment do
        find(".reactions__trigger").click
        find(".reaction__input").set content
        find(".reaction__submit-btn").click
      end
      assert_text content
    end

    def wait_for_cable_subscriptions
      assert_selector "turbo-cable-stream-source[connected]", visible: :all
      assert_no_selector "turbo-cable-stream-source:not([connected])", visible: :all
    end
end
