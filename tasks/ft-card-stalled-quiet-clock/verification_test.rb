require "test_helper"

class VerifierTest < ActionDispatch::IntegrationTest
  RECURRING_TASKS_IN_THE_BASE = %i[ auto_postpone_all_due delete_unused_tags clear_solid_queue_finished_jobs
    cleanup_webhook_deliveries cleanup_magic_links cleanup_exports cleanup_imports incineration yabeda_actioncable ]

  setup do
    @board = boards(:writebook)
    @author = users(:david)
    @other = users(:jz)
    sign_in_as :kevin
  end

  test "a card that never had a burst is never stalled" do
    card = card_named("Never had a burst")
    comment_on card, @author
    travel 30.days

    assert_not_includes stalled_listing, card.title
  end

  test "a stalled card says so where cards are shown" do
    quiet_since_burst = comment_burst_on(card_named("Burst, then dropped"))
    no_burst = card_named("No burst here")
    travel 30.days
    run_the_schedule

    get cards_path
    assert_select "##{dom_id(quiet_since_burst, :article)}"
    assert_match(/stall/i, css_select("##{dom_id(quiet_since_burst, :article)}").to_s)
    assert_select "##{dom_id(no_burst, :article)}"
    assert_no_match(/stall/i, css_select("##{dom_id(no_burst, :article)}").text)
    assert_not_includes stalled_listing, no_burst.title
  end

  test "a card that is still being talked about is not stalled" do
    card = comment_burst_on(card_named("Still going"))
    travel 30.days
    comment_on card, @author

    assert_not_includes stalled_listing, card.title
  end

  test "a card someone was assigned to or reopened and then left alone is stalled" do
    assigned = card_named("Assigned, then silence")
    reopened = card_named("Reopened, then silence")
    clear_enqueued_jobs

    with_current_user(@author) { reopened.close }
    perform_enqueued_jobs
    travel 1.hour
    with_current_user(@author) { assigned.toggle_assignment(@other) }
    with_current_user(@author) { reopened.reopen }
    perform_enqueued_jobs
    travel 30.days

    assert_includes stalled_listing, assigned.title
    assert_includes stalled_listing, reopened.title
  end

  test "ticking off a step clears a stalled card" do
    card = comment_burst_on(card_named("Steps, not comments"))
    step = with_current_user(@author) { card.steps.create!(content: "Ship it") }
    travel 30.days
    assert_includes stalled_listing, card.title

    with_current_user(@author) { step.update!(completed: true) }

    assert_not_includes stalled_listing, card.title
  end

  test "a card that had a burst and went quiet only briefly is not stalled" do
    card = comment_burst_on(card_named("Quiet for a few days"))
    travel 5.days

    assert_not_includes stalled_listing, card.title
  end

  test "a closed card is not listed as stalled" do
    card = comment_burst_on(card_named("Finished and quiet"))
    with_current_user(@author) { card.close }
    travel 30.days

    assert_not_includes stalled_listing, card.title
  end

  private
    def card_named(title)
      card = with_current_user(@author) { @board.cards.create!(title: title, creator: @author, status: :published) }
      Card.find(card.id)
    end

    def comment_burst_on(card)
      [ @author, @other, @author ].each do |user|
        travel 1.hour
        comment_on card, user
      end
      card.reload
    end

    def comment_on(card, user)
      travel 1.minute
      perform_enqueued_jobs do
        with_current_user(user) { card.comments.create!(creator: user, body: "Burst comment at #{Time.current.iso8601}") }
      end
      card.reload
    end

    def run_the_schedule
      clear_enqueued_jobs
      Rails.application.config_for(:recurring, env: "production").except(*RECURRING_TASKS_IN_THE_BASE).each_value do |task|
        task[:class] ? task[:class].constantize.perform_later(*task[:args]) : SolidQueue::RecurringJob.perform_later(task[:command])
      end
      loop { break if perform_enqueued_jobs.zero? }
    end

    def stalled_listing
      run_the_schedule
      get cards_path(indexed_by: :stalled)
      assert_response :success
      response.parsed_body.text
    end
end
