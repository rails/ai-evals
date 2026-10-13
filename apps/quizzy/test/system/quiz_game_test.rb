require "application_system_test_case"

class QuizGameTest < ApplicationSystemTestCase
  setup do
    @quiz = create_quiz(questions: 2, winners_count: 1)
  end

  test "moderator prepares a quiz" do
    login_as_moderator
    visit moderate_root_path
    click_on "New quiz"
    fill_in "Title", with: "Trivia RR"
    fill_in "Number of winners", with: "2"
    click_on "Save quiz"
    assert_text "Quiz created"

    click_on "Add question"
    fill_in "Question", with: "Who created Ruby?"
    rows = all(".option-row")
    rows[0].find("input[type=text]").fill_in(with: "Matz")
    rows[0].find("input[type=checkbox]").check
    rows[1].find("input[type=text]").fill_in(with: "DHH")
    click_on "+ Add option"
    all(".option-row").last.find("input[type=text]").fill_in(with: "Guido")
    click_on "Save question"

    assert_text "Question added"
    question = Quiz.find_by!(title: "Trivia RR").questions.sole
    assert_equal %w[Matz DHH Guido], question.option_titles
    assert_equal [0], question.correct_indexes

    within "##{dom_id(question)}" do
      uncheck "Active"
    end
    assert_selector ".question-item--inactive"
    assert_not question.reload.active?
  end

  test "full game with live updates for moderator and participants" do
    run = @quiz.runs.create!

    using_session(:moderator) do
      login_as_moderator
      visit moderate_run_path(run)
      assert_selector ".lobby__title", text: "Test quiz"
      assert_selector ".qr svg"
      assert_selector "#lobby_participants_counter", text: "0"
    end

    join(:alice, run, "Alice")
    join(:bob, run, "Bob")

    using_session(:moderator) do
      assert_selector "#lobby_participants_counter", text: "2"
      click_on "Start"
      assert_selector ".stage-question__body", text: "Question 1?"
      assert_selector "#answers_counter", text: "Answers: 0 / 2"
    end

    using_session(:alice) do
      assert_selector ".play-question__body", text: "Question 1?"
      click_on "Right 1"
      assert_text "Answer accepted"
    end

    using_session(:moderator) do
      assert_selector "#answers_counter", text: "Answers: 1 / 2"
    end

    using_session(:bob) do
      assert_selector ".play-question__body", text: "Question 1?"
      click_on "Right 1"
      assert_selector ".play-option.is-picked", text: "Right 1"
      # Changes the mind before the question is closed
      click_on "Wrong 1"
      assert_selector ".play-option.is-picked", text: "Wrong 1"
      assert_text "Answer accepted"
      assert_no_text "point"
    end

    using_session(:moderator) do
      assert_selector "#answers_counter", text: "Answers: 2 / 2"
      click_on "Finish"
      assert_selector ".stage-option.is-correct", text: "Right 1"
    end

    using_session(:alice) { assert_selector ".play-status--right", text: "Correct!" }
    using_session(:bob) { assert_selector ".play-status--wrong", text: "Wrong!" }

    using_session(:moderator) do
      click_on "Next"
      assert_selector ".stage-question__body", text: "Question 2?"
    end

    using_session(:bob) do
      assert_selector ".play-question__body", text: "Question 2?"
      click_on "Right 2"
      assert_text "Answer accepted"
    end

    using_session(:alice) do
      assert_selector ".play-question__body", text: "Question 2?"
      click_on "Right 2"
      assert_text "Answer accepted"
    end

    using_session(:moderator) do
      click_on "Finish"
      click_on "End quiz"
      assert_selector "h1", text: "Leaderboard"
      assert_selector ".leader", count: 2
      assert_selector ".leader:first-child .leader__name", text: "Alice"

      click_on "Top 1"
      assert_selector "h1", text: "Winners!"
      assert_selector ".leader.is-winner", count: 1, text: "Alice"
    end

    using_session(:alice) do
      assert_selector ".winner-banner", text: "You won!"
      assert_selector ".result-card__place", text: "1"
    end

    using_session(:bob) do
      assert_selector ".result-card__place", text: "2"
      assert_no_selector ".winner-banner"
    end
  end

  test "participant catches up after losing connection" do
    run = @quiz.runs.create!
    join(:alice, run, "Alice")

    using_session(:alice) do
      # Track WebSockets to be able to drop them (offline emulation alone keeps open sockets alive)
      page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
        const NativeWebSocket = window.WebSocket
        window.__sockets = []
        window.WebSocket = class extends NativeWebSocket {
          constructor(...args) { super(...args); window.__sockets.push(this) }
        }
      JS
      visit play_path(run)
      assert_selector "turbo-cable-stream-source[connected]"

      page.driver.browser.network.emulate_network_conditions(offline: true)
      page.execute_script("window.__sockets.forEach((ws) => ws.close())")
    end

    # The moderator starts the quiz while the phone is offline
    run.start!

    using_session(:alice) do
      assert_no_selector ".play-question__body"
      page.driver.browser.network.emulate_network_conditions(offline: false)
      # No manual reload: the client reconnects, restores the session and receives the missed refresh
      assert_selector ".play-question__body", text: "Question 1?", wait: 15
    end
  end

  test "the timer finishes the question by itself" do
    @quiz.update!(timer_seconds: 3)
    run = @quiz.runs.create!
    join(:alice, run, "Alice")

    using_session(:moderator) do
      login_as_moderator
      visit moderate_run_path(run)
      click_on "Start"
      assert_selector ".countdown", text: /0:0[1-3]/
    end

    using_session(:alice) do
      assert_selector ".play-question__body", text: "Question 1?"
      # Nobody clicks "Finish": the moderator's screen does it at 0:00
      assert_selector ".play-status--neutral", text: "No answer", wait: 10
    end

    using_session(:moderator) do
      assert_button "Next"
      assert_no_selector ".countdown"
    end
  end

  private

  def join(session, run, name)
    using_session(session) do
      visit play_path(run)
      fill_in "Your name", with: name
      click_on "Join"
      assert_text "Hi, #{name}!"
    end
  end
end
