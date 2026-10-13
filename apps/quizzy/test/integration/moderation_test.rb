require "test_helper"

class ModerationTest < ActionDispatch::IntegrationTest
  setup { @quiz = create_quiz(questions: 2) }

  test "requires basic auth" do
    get moderate_root_path
    assert_response :unauthorized

    get moderate_root_path, headers: {"HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("moderator", "wrong")}
    assert_response :unauthorized

    get moderate_root_path, headers: moderator_auth
    assert_response :success
    assert_select "h3", "Test quiz"
  end

  test "creates a quiz" do
    post moderate_quizzes_path, params: {quiz: {title: "New", winners_count: 5}}, headers: moderator_auth
    quiz = Quiz.last
    assert_redirected_to moderate_quiz_path(quiz)
    assert_equal ["New", 5], [quiz.title, quiz.winners_count]
  end

  test "creates a question from the indexed options form" do
    post moderate_quiz_questions_path(@quiz), headers: moderator_auth, params: {question: {
      body: "What is 2 + 2?", active: "1",
      options: {"0" => {title: "4", correct: "1"}, "1" => {title: "5", correct: "0"}, "17000" => {title: "", correct: "0"}}
    }}

    question = @quiz.questions.last
    assert_redirected_to moderate_quiz_path(@quiz, anchor: "question_#{question.id}")
    assert_equal [{"title" => "4", "correct" => true}, {"title" => "5", "correct" => false}], question.options
    assert_equal 2, question.position
  end

  test "re-renders the form when no option is correct" do
    post moderate_quiz_questions_path(@quiz), headers: moderator_auth, params: {question: {
      body: "?", options: {"0" => {title: "A", correct: "0"}, "1" => {title: "B", correct: "0"}}
    }}

    assert_response :unprocessable_entity
    assert_select ".errors", /Mark at least one option as correct/
  end

  test "toggles active flag and reorders questions" do
    first, second = @quiz.questions.to_a

    patch moderate_question_path(first), params: {question: {active: "0"}}, headers: moderator_auth
    assert_not first.reload.active?

    patch move_moderate_question_path(second, direction: :up), headers: moderator_auth
    assert_equal [second, first], @quiz.questions.reload.to_a
  end

  test "drives a run through all the states" do
    post moderate_quiz_runs_path(@quiz), headers: moderator_auth
    run = @quiz.runs.first
    assert_redirected_to moderate_run_path(run)

    get moderate_run_path(run), headers: moderator_auth
    assert_select ".lobby__title", "Test quiz"
    assert_select ".qr svg"
    assert_select ".lobby__url", "www.example.com/r/#{run.code}"

    post start_moderate_run_path(run), headers: moderator_auth
    get moderate_run_path(run), headers: moderator_auth
    assert_select ".stage-question__body", "Question 1?"
    assert_select "#answers_counter", /Answers: 0 \/ 0/
    assert_select "button", "Finish"

    post close_question_moderate_run_path(run), headers: moderator_auth
    get moderate_run_path(run), headers: moderator_auth
    assert_select ".stage-option.is-correct", /Right 1/
    assert_select "button", "Next"

    post advance_moderate_run_path(run), headers: moderator_auth
    post close_question_moderate_run_path(run), headers: moderator_auth
    get moderate_run_path(run), headers: moderator_auth
    assert_select "button", "End quiz"

    post advance_moderate_run_path(run), headers: moderator_auth
    assert run.reload.finished?
    get moderate_run_path(run), headers: moderator_auth
    assert_select "h1", "Leaderboard"
  end

  test "preview walks through questions and shows the total score" do
    get moderate_quiz_preview_path(@quiz), headers: moderator_auth
    assert_select ".play-question__body", "Question 1?"

    first, second = @quiz.questions.to_a
    post moderate_quiz_preview_path(@quiz), params: {question_id: first.id, option_index: 0, step: 0}, headers: moderator_auth
    assert_redirected_to moderate_quiz_preview_path(@quiz, step: 0)
    follow_redirect! headers: moderator_auth
    assert_select ".play-status--right"
    assert_select ".play-option.is-correct.is-picked"

    post moderate_quiz_preview_path(@quiz), params: {question_id: second.id, option_index: 1, step: 1}, headers: moderator_auth
    get moderate_quiz_preview_path(@quiz, step: 1), headers: moderator_auth
    assert_select ".play-status--wrong"

    get moderate_quiz_preview_path(@quiz, step: 2), headers: moderator_auth
    assert_select ".result-card__place", /Score: 1\/2/

    delete moderate_quiz_preview_path(@quiz), headers: moderator_auth
    get moderate_quiz_preview_path(@quiz, step: 2), headers: moderator_auth
    assert_select ".result-card__place", /Score: 0\/2/
  end
end
