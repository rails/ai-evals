# frozen_string_literal: true

# Step 1: the moderator prepares quizzes (auth, quizzes, questions, order, active flag, preview)
class AuthoringTest < E2E::Test
  test "the moderator area requires the moderator's credentials" do
    assert_equal 401, http_get("/moderate").code.to_i
    assert_equal 401, http_get("/moderate", auth: [ E2E::MODERATOR, "wrong" ]).code.to_i
    assert_equal 401, http_get("/moderate", auth: [ "intruder", E2E::PASSWORD ]).code.to_i
    assert_equal 200, http_get("/moderate", auth: [ E2E::MODERATOR, E2E::PASSWORD ]).code.to_i
  end

  test "the moderator creates a quiz with questions" do
    title = unique("Trivia")
    as_moderator do
      create_quiz(title)
      add_question("Which planet is the largest?", [ [ "Jupiter", true ], [ "Saturn" ], [ "Earth" ] ])
      add_question("Which numbers are prime?", [ [ "2", true ], [ "4" ], [ "7", true ], [ "9" ], [ "10" ] ])

      visit "/moderate"
      assert_text title
      open_quiz(title)
      within(item("Which planet is the largest?")) do
        assert_text "Jupiter"
        assert_text "Saturn"
        assert_text "Earth"
      end
      # Five options: the form adds a fifth row on "Add option"
      within(item("Which numbers are prime?")) { assert_text "10" }
      assert_operator page.text.index("Which planet is the largest?"), :<, page.text.index("Which numbers are prime?")
    end
  end

  test "a question needs two options and a correct one" do
    as_moderator do
      create_quiz(unique("Rules"))

      click_on "Add question", match: :first
      fill_in "Question", with: "Lonely option?"
      fill_in "Option 1", with: "Only me"
      check "Option 1 is correct", allow_label_click: true
      click_on "Save question", match: :first
      assert_text "Add at least two options"
      assert_field "Question", with: "Lonely option?"

      fill_in "Question", with: "Nothing is right?"
      fill_option(1, "Only me")
      fill_option(2, "Not me")
      uncheck "Option 1 is correct", allow_label_click: true
      click_on "Save question", match: :first
      assert_text "Mark at least one option as correct"
      assert_field "Question", with: "Nothing is right?"

      fill_option(1, "Only me")
      fill_option(2, "Not me")
      check "Option 2 is correct", allow_label_click: true
      click_on "Save question", match: :first
      assert_no_field "Question"
      assert_text "Nothing is right?"
      assert_no_text "Lonely option?"
    end
  end

  test "the moderator edits and deletes questions" do
    as_moderator do
      create_quiz(unique("Edits"))
      add_question("Speed of light?", [ [ "300,000 km/s", true ], [ "3,000 km/s" ] ])
      add_question("To be deleted?", [ [ "Yes", true ], [ "No" ] ])

      within(item("Speed of light?")) { click_on "Edit", match: :first }
      fill_in "Question", with: "Speed of light in vacuum?"
      fill_in "Option 2", with: "30,000 km/s"
      click_on "Save question", match: :first
      assert_no_field "Question"
      within(item("Speed of light in vacuum?")) { assert_text "30,000 km/s" }

      accept_confirm { within(item("To be deleted?")) { click_on "Delete", match: :first } }
      assert_no_text "To be deleted?"
      refresh
      assert_text "Speed of light in vacuum?"
      assert_no_text "To be deleted?"
    end
  end

  test "the moderator reorders questions" do
    as_moderator do
      create_quiz(unique("Order"))
      add_question("First question?", [ [ "A1", true ], [ "B1" ] ])
      add_question("Second question?", [ [ "A2", true ], [ "B2" ] ])
      add_question("Third question?", [ [ "A3", true ], [ "B3" ] ])

      within(item("Third question?")) { click_on "Move up", match: :first }
      assert_order "First question?", "Third question?", "Second question?"
      within(item("First question?")) { click_on "Move down", match: :first }
      assert_order "Third question?", "First question?", "Second question?"
      refresh
      assert_order "Third question?", "First question?", "Second question?"

      # A new question goes last, after the moved ones (equal positions keep a 3-question swap
      # working but put a new question anywhere), and it moves like the others
      add_question("Fourth question?", [ [ "A4", true ], [ "B4" ] ])
      assert_order "Third question?", "First question?", "Second question?", "Fourth question?"
      within(item("Fourth question?")) { click_on "Move up", match: :first }
      assert_order "Third question?", "First question?", "Fourth question?", "Second question?"
      refresh
      assert_order "Third question?", "First question?", "Fourth question?", "Second question?"
    end
  end

  test "the active switch saves at once and the preview skips inactive questions" do
    title = unique("Active")
    as_moderator do
      create_quiz(title)
      add_question("Kept question?", [ [ "Keep", true ], [ "Drop" ] ])
      add_question("Skipped question?", [ [ "Skip", true ], [ "Stay" ] ])
      add_question("Draft question?", [ [ "Draft", true ], [ "Final" ] ], active: false)

      within(item("Skipped question?")) { uncheck "Active", allow_label_click: true }
      sleep 1
      finish_pending_posts
      refresh
      within(item("Skipped question?")) { assert_unchecked_field "Active", visible: :all }
      within(item("Draft question?")) { assert_unchecked_field "Active", visible: :all }
      within(item("Kept question?")) { assert_checked_field "Active", visible: :all }

      click_on "Preview", match: :first
      assert_phrase "Question 1 of 1"
      assert_text "Kept question?"
      assert_no_text "Skipped question?"
      assert_no_text "Draft question?"
    end
  end

  test "the preview walks through the quiz and shows the score" do
    as_moderator do
      create_quiz(unique("Preview"))
      add_question("Capital of France?", [ [ "Paris", true ], [ "Lyon" ], [ "Nice" ] ])
      add_question("Two plus two?", [ [ "Three" ], [ "Four", true ] ])
      add_question("Primary colors?", [ [ "Red", true ], [ "Green" ], [ "Blue", true ] ])

      click_on "Preview", match: :first
      assert_phrase "Question 1 of 3"
      assert_text "Capital of France?"
      click_on "Lyon", match: :first
      assert_text "Wrong!"
      click_on "Next question", match: :first

      assert_phrase "Question 2 of 3"
      click_on "Four", match: :first
      assert_text "Correct!"
      click_on "Next question", match: :first

      # Several correct options: any of them is right
      assert_phrase "Question 3 of 3"
      click_on "Blue", match: :first
      assert_text "Correct!"
      click_on "See score", match: :first
      assert_text %r{Score:\s*2\s*/\s*3}

      click_on "Start over", match: :first
      assert_phrase "Question 1 of 3"
      assert_text "Capital of France?"
    end
  end

  test "the moderator renames and deletes a quiz" do
    title = unique("Old name")
    renamed = unique("New name")
    as_moderator do
      create_quiz(title)
      click_on "Settings", match: :first
      fill_in "Title", with: renamed
      click_on "Save quiz", match: :first
      assert_text renamed

      visit "/moderate"
      assert_text renamed
      assert_no_text title

      open_settings(renamed)
      accept_confirm { click_on "Delete quiz", match: :first }
      assert_no_text renamed
      visit "/moderate"
      assert_no_text renamed
    end
  end

  private
    def assert_order(*texts)
      eventually(timeout: 10) do
        positions = texts.map { page.text.index(it) }
        positions.all? && positions == positions.sort
      end
      positions = texts.map { page.text.index(it) }
      assert positions.all?, "missing questions: #{texts.zip(positions).select { !it.last }.map(&:first)}"
      assert_equal positions.sort, positions, "expected the order #{texts.inspect}"
    end
end
