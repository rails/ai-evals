require "test_helper"

class ImportExportTest < ActionDispatch::IntegrationTest
  setup do
    @quiz = create_quiz(questions: 2)
    @quiz.questions.last.update!(active: false)
  end

  test "exports the quiz structure as JSON" do
    get moderate_quiz_export_path(@quiz), headers: moderator_auth
    assert_response :success

    data = JSON.parse(css_select("pre").text)
    assert_equal "Test quiz", data["title"]
    assert_equal [true, false], data["questions"].map { it["active"] }
    assert_equal({"text" => "Question 1?", "active" => true,
                  "options" => [{"text" => "Right 1", "correct" => true}, {"text" => "Wrong 1", "correct" => false}]},
      data["questions"].first)
  end

  test "imports an exported quiz as a new one" do
    assert_difference -> { Quiz.count } => 1, -> { Question.count } => 2 do
      post moderate_import_path, params: {json: @quiz.export.to_json}, headers: moderator_auth
    end
    copy = Quiz.order(:id).last
    assert_redirected_to moderate_quiz_path(copy)
    assert_equal @quiz.export, copy.export
  end

  test "defaults: active questions and wrong options" do
    json = {title: "Defaults", questions: [{text: "Q?", options: [{text: "A", correct: true}, {text: "B"}]}]}.to_json
    post moderate_import_path, params: {json:}, headers: moderator_auth

    question = Quiz.find_by!(title: "Defaults").questions.sole
    assert question.active?
    assert_equal [0], question.correct_indexes
  end

  test "imports all or nothing" do
    json = {title: "Broken", questions: [
      {text: "Fine?", options: [{text: "A", correct: true}, {text: "B"}]},
      {text: "No correct option?", options: [{text: "A"}, {text: "B"}]}
    ]}.to_json

    assert_no_difference -> { Quiz.count } do
      post moderate_import_path, params: {json:}, headers: moderator_auth
    end
    assert_response :unprocessable_entity
    assert_select ".errors", /Question 2: Mark at least one option as correct/
  end

  test "rejects invalid JSON" do
    assert_no_difference -> { Quiz.count } do
      post moderate_import_path, params: {json: "{oops"}, headers: moderator_auth
    end
    assert_response :unprocessable_entity
    assert_select ".errors", /not valid JSON/
  end

  test "requires the moderator" do
    get moderate_quiz_export_path(@quiz)
    assert_response :unauthorized
    post moderate_import_path, params: {json: @quiz.export.to_json}
    assert_response :unauthorized
  end
end
