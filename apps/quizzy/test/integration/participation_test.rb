require "test_helper"

class ParticipationTest < ActionDispatch::IntegrationTest
  setup do
    @quiz = create_quiz(questions: 2)
    @run = @quiz.runs.create!
    @q1 = @quiz.questions.first
  end

  test "joins with a name and stays identified by the session" do
    get play_path(@run)
    assert_select "input[name=name]"

    post participation_path(code: @run.code), params: {name: "  Matz  "}
    assert_redirected_to play_path(@run)
    participation = @run.participations.sole
    assert_equal "Matz", participation.name
    assert participation.uid.present?
    assert cookies[:participant_uid].present?

    follow_redirect!
    assert_select "h1", "Hi, Matz!"

    # Joining twice doesn't create another participation
    post participation_path(code: @run.code), params: {name: "Matz"}
    assert_equal 1, @run.participations.count
  end

  test "codes are case-insensitive" do
    get play_path(code: @run.code.downcase)
    assert_response :success
  end

  test "rejects a blank name" do
    post participation_path(code: @run.code), params: {name: " "}
    assert_response :unprocessable_entity
    assert_equal 0, @run.participations.count
  end

  test "answers the current question and may change the answer while it's open" do
    post participation_path(code: @run.code), params: {name: "Alice"}
    participation = @run.participations.sole

    post answers_path(code: @run.code), params: {question_id: @q1.id, option_index: 0}
    assert_equal 0, participation.answers.count, "not accepted before the start"

    @run.start!
    get play_path(@run)
    assert_select "button.play-option", 2

    post answers_path(code: @run.code), params: {question_id: @q1.id, option_index: 0}
    assert_equal 1, participation.reload.score

    post answers_path(code: @run.code), params: {question_id: @q1.id, option_index: 1}
    assert_equal [1], participation.answers.pluck(:option_index)
    assert_equal 0, participation.reload.score

    get play_path(@run)
    assert_select "button.play-option.is-picked", /Wrong 1/
    assert_select ".play-status", /Answer accepted/
    assert_select ".play__top", text: /point/, count: 0

    post answers_path(code: @run.code), params: {question_id: @q1.id, option_index: 0}
    assert_equal 1, participation.reload.score
    assert_equal 1, participation.answers.count

    @run.close_question!
    get play_path(@run)
    assert_select ".play-status--right", /Correct!/

    @run.advance!
    @run.close_question!
    post answers_path(code: @run.code), params: {question_id: @quiz.questions.second.id, option_index: 0}
    assert_equal 1, participation.answers.count, "closed question doesn't accept answers"

    get play_path(@run)
    assert_select ".play-status--neutral", /No answer/

    @run.advance!
    @run.pick_winners!
    get play_path(@run)
    assert_select ".result-card__place", "1"
    assert_select ".winner-banner", /You won/
  end

  test "late joiners can not join a finished quiz" do
    @run.update!(state: :finished)
    get play_path(@run)
    assert_select "input[name=name]", 0
    assert_select ".play-lead", /The quiz is over/

    post participation_path(code: @run.code), params: {name: "Latecomer"}
    assert_equal 0, @run.participations.count
  end
end
