require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  setup { @quiz = Quiz.create!(title: "Quiz") }

  test "normalizes options from an indexed form hash and drops blank rows" do
    question = @quiz.questions.create!(body: "?", options: {
      "0" => {"title" => " Yes ", "correct" => "1"},
      "1" => {"title" => "No", "correct" => "0"},
      "2" => {"title" => "", "correct" => "1"}
    })

    assert_equal [{"title" => "Yes", "correct" => true}, {"title" => "No", "correct" => false}], question.options
    assert question.correct_option?(0)
    assert_not question.correct_option?(1)
    assert_equal [0], question.correct_indexes
  end

  test "requires at least two options and one correct" do
    question = @quiz.questions.new(body: "?", options: [{title: "Single", correct: true}])
    assert_not question.valid?
    assert_includes question.errors[:base], "Add at least two options"

    question.options = [{title: "A", correct: false}, {title: "B", correct: false}]
    assert_not question.valid?
    assert_includes question.errors[:base], "Mark at least one option as correct"

    question.options = [{title: "A", correct: true}, {title: "B", correct: true}]
    assert question.valid?
  end

  test "appends to the end and moves up and down" do
    quiz = create_quiz(questions: 3)
    first, second, third = quiz.questions.to_a
    assert_equal [0, 1, 2], [first, second, third].map(&:position)

    third.move!(:up)
    assert_equal [first, third, second], quiz.questions.reload.to_a

    first.move!(:up) # no-op at the top
    first.reload.move!(:down)
    assert_equal [third, first, second], quiz.questions.reload.to_a
  end

  test "cannot be deleted while on screen, but the whole quiz can" do
    quiz = create_quiz(questions: 2)
    run = quiz.runs.create!
    run.start!

    current = run.current_question
    assert_not current.destroy
    assert Question.exists?(current.id)
    assert quiz.questions.second.destroy

    quiz.destroy!
    assert_not Run.exists?(run.id)
  end
end
