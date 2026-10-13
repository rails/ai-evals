# frozen_string_literal: true

# Step 4: points, the leaderboard, and picking the winners
class ScoringTest < E2E::Test
  test "the leaderboard ranks players by points, then by speed" do
    title = unique("Ranks")
    as_moderator do
      import_quiz(quiz_data(title, [
        [ "Which metal is liquid at room temperature?", [ [ "Mercury", true ], [ "Iron" ], [ "Gold" ] ] ],
        [ "Which ocean is the largest?", [ [ "Atlantic" ], [ "Pacific", true ], [ "Arctic" ] ] ]
      ]))
    end
    url = as_moderator { start_game(title) }
    # Dave joins first, so ranking ties by join order instead of speed shows
    %w[Dave Carol Bob Alice].each { join(it, url) }

    moderator_click "Start"
    as_player("Dave") { assert_text "Which metal is liquid", wait: E2E::LIVE_WAIT }
    answer "Alice", "Mercury" # right and fast
    answer "Bob", "Mercury"
    answer "Carol", "Iron"
    as_player("Alice") { assert_no_points }
    sleep 3
    answer "Dave", "Mercury" # right, but slow
    assert_answers_counter 4, 4
    moderator_click "Finish"
    as_player("Alice") do
      assert_text "Correct!", wait: E2E::LIVE_WAIT
      assert_no_points
    end

    moderator_click "Next"
    as_player("Bob") { assert_text "Which ocean is the largest?", wait: E2E::LIVE_WAIT }
    answer "Bob", "Pacific"
    answer "Alice", "Atlantic"
    answer "Dave", "Arctic"
    assert_answers_counter 3, 4
    moderator_click "Finish"
    moderator_click "End quiz"

    as_moderator do
      assert_text "Bob", wait: 15
      expected = { "Bob" => "2 points", "Alice" => "1 point", "Dave" => "1 point", "Carol" => "0 points" }
      expected.each { |name, points| within(item(name)) { assert_text(/\b#{points}\b/) } }
      positions = expected.keys.map { |name| page.text.index(name) }
      assert_equal positions.sort, positions, "expected the leaderboard order Bob, Alice, Dave, Carol"
    end

    { "Bob" => [ 1, "2 points" ], "Alice" => [ 2, "1 point" ], "Dave" => [ 3, "1 point" ], "Carol" => [ 4, "0 points" ] }.each do |name, (place, points)|
      as_player(name) do
        assert_phrase "Place #{place} of 4", wait: E2E::LIVE_WAIT
        assert_text(/\b#{points}\b/)
      end
    end
  end

  test "the top players win, nobody wins with zero points, and winners can be reset" do
    title = unique("Prizes")
    as_moderator do
      import_quiz(quiz_data(title, [ [ "Which is a primary color?", [ [ "Blue", true ], [ "Pink" ], [ "Brown" ] ] ] ]))
      open_settings(title)
      assert_field "Number of winners", with: "3"
    end
    url = as_moderator { start_game(title) }
    %w[Ann Ben Cid Dee].each { join(it, url) }

    moderator_click "Start"
    as_player("Dee") { assert_text "Which is a primary color?", wait: E2E::LIVE_WAIT }
    answer "Ann", "Blue"
    sleep 1
    answer "Ben", "Blue"
    answer "Cid", "Pink"
    assert_answers_counter 3, 4
    moderator_click "Finish"
    moderator_click "End quiz"

    # Three prizes, but only two players have points
    moderator_click "Top 3"
    as_moderator do
      within(item("Ann")) { assert_text "Winner", wait: 15 }
      within(item("Ben")) { assert_text "Winner" }
      within(item("Cid")) { assert_no_text "Winner" }
      within(item("Dee")) { assert_no_text "Winner" }
    end
    as_player("Ann") { assert_text "You won!", wait: E2E::LIVE_WAIT }
    as_player("Ben") { assert_text "You won!", wait: E2E::LIVE_WAIT }
    as_player("Cid") { assert_no_text "You won!" }

    moderator_click "Draw"
    as_moderator do
      sleep 1
      within(item("Ann")) { assert_text "Winner" }
      within(item("Ben")) { assert_text "Winner" }
      within(item("Cid")) { assert_no_text "Winner" }
    end

    moderator_click "Reset winners"
    as_moderator do
      within(item("Ann")) { assert_no_text "Winner", wait: 15 }
      within(item("Ben")) { assert_no_text "Winner" }
    end
    as_player("Ann") { assert_no_text "You won!", wait: E2E::LIVE_WAIT }
  end

  test "a draw keeps the clear winners and picks at random among the tied" do
    title = unique("Tiebreak")
    as_moderator do
      import_quiz(quiz_data(title, [
        [ "Which animal barks?", [ [ "Dog", true ], [ "Cat" ] ] ],
        [ "Which animal meows?", [ [ "Dog" ], [ "Cat", true ] ] ]
      ]))
      save_settings(title, "Number of winners" => 2)
    end
    url = as_moderator { start_game(title) }
    %w[Ann Ben Cid Dee].each { join(it, url) }

    moderator_click "Start"
    as_player("Dee") { assert_text "Which animal barks?", wait: E2E::LIVE_WAIT }
    answer "Ann", "Dog"
    answer "Ben", "Dog"
    answer "Cid", "Cat"
    answer "Dee", "Cat"
    assert_answers_counter 4, 4
    moderator_click "Finish"
    moderator_click "Next"
    as_player("Dee") { assert_text "Which animal meows?", wait: E2E::LIVE_WAIT }
    answer "Ann", "Cat"
    answer "Cid", "Cat"
    answer "Ben", "Dog"
    answer "Dee", "Dog"
    assert_answers_counter 4, 4
    moderator_click "Finish"
    moderator_click "End quiz"
    # Ann: 2 points; Ben and Cid: 1 point each; Dee: 0

    as_moderator { assert_button "Top 2" }
    seen = []
    15.times do
      moderator_click "Draw"
      as_moderator do
        winners = []
        eventually(timeout: 10) do
          # The leaderboard re-renders after each draw: an element can go stale under the read
          winners = %w[Ann Ben Cid Dee].select { |name| item(name).has_text?("Winner", wait: 0) }
          winners.size == 2
        rescue Capybara::ElementNotFound, Capybara::Cuprite::ObsoleteNode, Ferrum::NodeNotFoundError
          false
        end
        assert_equal 2, winners.size, "expected two winners after a draw, got #{winners.inspect}"
        assert_includes winners, "Ann", "the player above the cutoff always wins"
        refute_includes winners, "Dee", "a player with 0 points never wins"
        seen << (winners - [ "Ann" ]).first
      end
      break if seen.uniq.size == 2
    end
    assert_equal %w[Ben Cid], seen.uniq.sort, "the draw always picked the same tied player"
  end

  private
    def assert_no_points
      sleep 0.5
      assert_no_text(/\b\d+ points?\b/i)
    end
end
