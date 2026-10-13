require "test_helper"

class ResponsesTest < ActionDispatch::IntegrationTest
  setup do
    @quiz = create_quiz(questions: 2)
    @q1, @q2 = @quiz.questions.to_a
    @run = @quiz.runs.create!
    @alice = @run.participations.create!(name: "Alice", uid: "a")
    @bob = @run.participations.create!(name: "Bob", uid: "b")

    @run.start!
    @alice.answers.create!(question: @q1, option_index: 0)
    @bob.answers.create!(question: @q1, option_index: 1)
    @run.close_question!
    @run.advance!
    @alice.answers.create!(question: @q2, option_index: 0)
    @run.close_question!
  end

  test "moderators only" do
    finish!
    get moderate_run_responses_path(@run)
    assert_response :unauthorized

    get moderate_run_participant_response_path(@run, @alice)
    assert_response :unauthorized
  end

  test "only available after the run is finished" do
    get moderate_run_responses_path(@run), headers: moderator_auth
    assert_redirected_to moderate_run_path(@run)

    get moderate_run_question_response_path(@run, @q1), headers: moderator_auth
    assert_redirected_to moderate_run_path(@run)
  end

  test "summary by questions and by participants" do
    finish!

    get moderate_run_responses_path(@run), headers: moderator_auth
    assert_response :success
    assert_select "#question_#{@q1.id}", text: /Question 1\?.*2 \/ 2.*1\s*\(50%\)/m
    assert_select "#question_#{@q2.id}", text: /Question 2\?.*1 \/ 2.*1\s*\(100%\)/m

    get moderate_run_responses_path(@run, tab: "participants"), headers: moderator_auth
    assert_select "tbody tr", 2
    assert_select "tbody tr:first-child", text: /1.*Alice.*2/m
    assert_select "tbody tr:last-child", text: /2.*Bob.*0/m
  end

  test "all answers to a question" do
    finish!

    get moderate_run_question_response_path(@run, @q2), headers: moderator_auth
    assert_response :success
    assert_select "h1", "Question 2?"
    assert_select ".response-option.is-correct", text: /A\. Right 2\s*1/
    assert_select "#participation_#{@alice.id}", text: /Alice.*A\. Right 2.*correct/m
    assert_select "#participation_#{@bob.id}", text: /Bob.*—.*no answer/m
    assert_select "a", text: "← Previous question"
    assert_select "a", text: "Next question →", count: 0
  end

  test "all answers of a participant" do
    finish!

    get moderate_run_participant_response_path(@run, @bob), headers: moderator_auth
    assert_response :success
    assert_select "h1", /Bob/
    assert_select ".meta", /Place 2 of 2/
    assert_select "#question_#{@q1.id} .mark--wrong"
    assert_select "#question_#{@q1.id} li.is-picked", "B. Wrong 1"
    assert_select "#question_#{@q2.id} .mark--none"
    assert_select "a", text: "← Alice"
  end

  test "questions and participants of another run are not found" do
    finish!
    other = create_quiz(questions: 1)
    other_run = other.runs.create!
    stranger = other_run.participations.create!(name: "Stranger", uid: "x")

    get moderate_run_question_response_path(@run, other.questions.first), headers: moderator_auth
    assert_response :not_found

    get moderate_run_participant_response_path(@run, stranger), headers: moderator_auth
    assert_response :not_found
  end

  private

  def finish! = @run.advance!
end
