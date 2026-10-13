require "test_helper"
require "turbo/broadcastable/test_helper"

class RunTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @quiz = create_quiz(questions: 2, winners_count: 2)
    @q1, @q2 = @quiz.questions.to_a
    @run = @quiz.runs.create!
  end

  test "generates a unique code" do
    assert_match(/\A[A-Z2-9]{5}\z/, @run.code)
    assert_equal @run.code, @run.to_param
  end

  test "goes through the whole game flow, skipping inactive questions" do
    inactive = @quiz.questions.create!(body: "Hidden", options: [{title: "a", correct: true}, {title: "b"}], active: false)
    assert_equal [@q1, @q2], @run.questions

    assert @run.idle?
    assert_turbo_stream_broadcasts(@run) { @run.start! }
    assert @run.running?
    assert @run.showing_question?
    assert_equal @q1, @run.current_question
    assert_equal 1, @run.current_question_number
    assert @run.accepting_answers_for?(@q1)

    @run.advance! # ignored while the question is open
    assert_equal @q1, @run.current_question

    @run.close_question!
    assert @run.showing_results?
    assert_not @run.accepting_answers_for?(@q1)
    assert_not @run.last_question?

    @run.advance!
    assert_equal @q2, @run.current_question
    assert @run.showing_question?

    @run.close_question!
    assert @run.last_question?
    @run.advance!
    assert @run.finished?
    assert_nil @run.question_state
    assert_not_equal inactive, @run.current_question
  end

  test "cannot start without active questions" do
    @quiz.questions.update_all(active: false)
    assert_raises(ArgumentError) { @run.start! }
  end

  test "scores answers and ranks by score then by time" do
    alice = @run.participations.create!(name: "Alice", uid: "a")
    bob = @run.participations.create!(name: "Bob", uid: "b")
    carol = @run.participations.create!(name: "Carol", uid: "c")

    freeze_time
    @run.start!
    travel 2.seconds do
      bob.answers.create!(question: @q1, option_index: 0)
    end
    travel 5.seconds do
      alice.answers.create!(question: @q1, option_index: 0)
      carol.answers.create!(question: @q1, option_index: 1)
    end

    assert_equal [1, 1, 0], [alice, bob, carol].map { it.reload.score }
    assert_equal 2000, bob.correct_time_ms
    assert_not carol.answers.first.correct?
    assert_equal [bob, alice, carol], @run.leaderboard.to_a
    assert_equal 1, bob.place
  end

  test "recalculates the score when an answer changes" do
    alice = @run.participations.create!(name: "Alice", uid: "a")
    freeze_time
    @run.start!

    answer = travel(1.second) { alice.answers.create!(question: @q1, option_index: 1) }
    assert_equal [0, 0], [alice.reload.score, alice.correct_time_ms]

    travel(3.seconds) { answer.update!(option_index: 0) }
    assert answer.correct?
    assert_equal [1, 3000], [alice.reload.score, alice.correct_time_ms]

    travel(4.seconds) { answer.update!(option_index: 1) }
    assert_equal [0, 0], [alice.reload.score, alice.correct_time_ms]
  end

  test "rejects a second answer record for the same question" do
    alice = @run.participations.create!(name: "Alice", uid: "a")
    @run.start!
    alice.answers.create!(question: @q1, option_index: 1)
    second = alice.answers.create(question: @q1, option_index: 0)

    assert_not second.persisted?
    assert_equal 0, alice.reload.score
  end

  test "broadcasts answer counter to moderators" do
    alice = @run.participations.create!(name: "Alice", uid: "a")
    @run.start!

    assert_turbo_stream_broadcasts([@run, :moderator], count: 1) do
      alice.answers.create!(question: @q1, option_index: 0)
    end
  end

  test "picks top N winners or draws among cutoff ties" do
    finish_with_scores(10 => 2, 20 => 1, 30 => 1, 40 => 1, 50 => 0)
    top, *tied = @run.leaderboard.where("score > 0").to_a

    assert_equal 3, @run.cutoff_ties.size

    @run.pick_winners!
    assert_equal [top, tied.first], @run.winners.to_a

    draws = 20.times.map do
      @run.pick_winners!(random: true)
      winners = @run.winners.to_a
      assert_equal 2, winners.size
      assert_includes winners, top
      winners.find { it != top }
    end
    assert_operator draws.uniq.size, :>, 1, "expected different tied participants to win"

    @run.reset_winners!
    assert_empty @run.winners
  end

  test "participants without points never win" do
    finish_with_scores(10 => 1, 20 => 0, 30 => 0)
    @run.pick_winners!(random: true)
    assert_equal 1, @run.winners.count
    assert_empty @run.cutoff_ties
  end

  test "stale transitions are no-ops" do
    @run.start!
    stale = Run.find(@run.id)

    @run.close_question!
    @run.advance!
    started_at = @run.question_started_at

    # A second tab still thinks question 1 is showing results
    stale.question_state = "results"
    assert_not stale.advance!
    assert_equal @q2, stale.current_question
    assert_equal started_at, @run.reload.question_started_at
  end

  test "place matches leaderboard order" do
    finish_with_scores(30 => 2, 10 => 2, 20 => 1, 5 => 0)
    @run.leaderboard.each_with_index { |participation, i| assert_equal i + 1, participation.place }
  end

  private

  # {elapsed_ms => score}
  def finish_with_scores(scores)
    scores.each_with_index do |(ms, score), i|
      @run.participations.create!(name: "P#{i}", uid: "u#{i}", score:, correct_time_ms: ms)
    end
    @run.update!(state: :finished)
  end
end
