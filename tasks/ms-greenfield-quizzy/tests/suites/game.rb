# frozen_string_literal: true

# Step 3: the live game, on the big screen (moderator) and on the phones (players)
class GameTest < E2E::Test
  QUESTIONS = [
    [ "Which planet is closest to the Sun?", [ [ "Mercury", true ], [ "Venus" ], [ "Mars" ] ] ],
    [ "Which gas do plants absorb?", [ [ "Oxygen" ], [ "Carbon dioxide", true ], [ "Helium" ] ] ],
    [ "Skipped draft question?", [ [ "Draft yes", true ], [ "Draft no" ] ], false ],
    [ "How many legs does a spider have?", [ [ "Six" ], [ "Eight", true ], [ "Ten" ] ] ]
  ].freeze

  def setup
    super
    @title = unique("Live")
    as_moderator { import_quiz(quiz_data(@title, QUESTIONS)) }
  end

  test "the lobby shows the join link and counts players live" do
    url = as_moderator { start_game(@title) }
    as_moderator do
      assert_text @title
      assert_text(/Players:\s*0\b/)
      assert_selector "svg, img, canvas", minimum: 1 # the QR code
    end

    join("Alice", url)
    as_player("Alice") { assert_text "Hi, Alice!" }
    as_moderator { assert_text(/Players:\s*1\b/, wait: E2E::LIVE_WAIT) }
    join("Bob", url)
    as_moderator { assert_text(/Players:\s*2\b/, wait: E2E::LIVE_WAIT) }
  end

  test "players follow the moderator through the whole game" do
    url = as_moderator { start_game(@title) }
    join("Alice", url)
    join("Bob", url)
    as_moderator { assert_text(/Players:\s*2\b/, wait: E2E::LIVE_WAIT) }

    moderator_click "Start"
    as_moderator do
      assert_phrase "Question 1 of 3"
      assert_text "Which planet is closest to the Sun?"
    end
    assert_answers_counter 0, 2
    %w[Alice Bob].each do |name|
      as_player(name) { assert_text "Which planet is closest to the Sun?", wait: E2E::LIVE_WAIT }
    end

    answer "Alice", "Mercury"
    assert_answers_counter 1, 2
    answer "Bob", "Venus"
    assert_answers_counter 2, 2

    moderator_click "Finish"
    as_moderator do
      within(item("Mercury")) do
        assert_text "Correct"
        assert_text(/\b1\b/)
      end
      within(item("Venus")) do
        assert_no_text "Correct"
        assert_text(/\b1\b/)
      end
      within(item("Mars")) { assert_text(/\b0\b/) }
    end
    as_player("Alice") { assert_text "Correct!", wait: E2E::LIVE_WAIT }
    as_player("Bob") { assert_text "Wrong!", wait: E2E::LIVE_WAIT }

    moderator_click "Next"
    as_moderator { assert_phrase "Question 2 of 3" }
    as_player("Alice") { assert_text "Which gas do plants absorb?", wait: E2E::LIVE_WAIT }
    answer "Bob", "Carbon dioxide"
    assert_answers_counter 1, 2
    moderator_click "Finish"
    as_player("Alice") { assert_text "No answer", wait: E2E::LIVE_WAIT }
    as_player("Bob") { assert_text "Correct!", wait: E2E::LIVE_WAIT }

    # The draft question is skipped
    moderator_click "Next"
    as_moderator do
      assert_phrase "Question 3 of 3"
      assert_text "How many legs does a spider have?"
      assert_no_button "Next"
    end
    as_player("Bob") { assert_text "How many legs does a spider have?", wait: E2E::LIVE_WAIT }
    moderator_click "Finish"
    moderator_click "End quiz"

    as_moderator { assert_text "The quiz is over" }
    %w[Alice Bob].each { |name| as_player(name) { assert_text "The quiz is over", wait: E2E::LIVE_WAIT } }
  end

  test "players change their answer until the question closes" do
    url = as_moderator { start_game(@title) }
    join("Alice", url)
    join("Bob", url)
    moderator_click "Start"
    as_player("Alice") { assert_text "Which planet is closest to the Sun?", wait: E2E::LIVE_WAIT }

    answer "Alice", "Venus"
    assert_answers_counter 1, 2
    answer "Alice", "Mars"
    answer "Alice", "Mercury"
    # Changes don't count as more answers
    as_moderator do
      sleep 1
      assert_text(%r{Answers:\s*1\s*/\s*2})
    end

    moderator_click "Finish"
    as_player("Alice") { assert_text "Correct!", wait: E2E::LIVE_WAIT }
    as_moderator do
      within(item("Mercury")) { assert_text(/\b1\b/) }
      within(item("Venus")) { assert_text(/\b0\b/) }
    end
  end

  test "the browser remembers the player, late players join, and the end closes the door" do
    url = as_moderator { start_game(@title) }
    join("Alice", url)
    as_player("Alice") do
      visit url
      assert_text "Hi, Alice!"
      assert_no_field "Your name"
    end
    as_moderator { assert_text(/Players:\s*1\b/, wait: E2E::LIVE_WAIT) }

    moderator_click "Start"
    # Late, but in time for the first question
    join("Carol", url, expect: "Which planet is closest to the Sun?")
    as_player("Carol") { assert_text "Which planet is closest to the Sun?", wait: E2E::LIVE_WAIT }
    answer "Carol", "Mercury"
    assert_answers_counter 1, 2

    moderator_click "Finish"
    as_player("Carol") { assert_text "Correct!", wait: E2E::LIVE_WAIT }
    2.times do
      moderator_click "Next"
      moderator_click "Finish"
    end
    moderator_click "End quiz"
    as_moderator { assert_text "The quiz is over" }

    as_player("Dave") do
      visit url
      assert_text "The quiz is over"
      assert_no_field "Your name"
    end
  end

  test "each game starts fresh and the big screen survives a reload" do
    first = as_moderator { start_game(@title) }
    join("Alice", first)
    moderator_click "Start"
    as_moderator do
      refresh
      assert_text "Which planet is closest to the Sun?"
      assert_button "Finish"
    end
    as_player("Alice") do
      refresh
      assert_text "Which planet is closest to the Sun?"
    end

    second = as_moderator { start_game(@title) }
    refute_equal first, second, "a new game needs its own join link"
    as_moderator do
      assert_text(/Players:\s*0\b/)
      assert_button "Start"
    end
  end
end
