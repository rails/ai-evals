class Run < ApplicationRecord
  CODE_ALPHABET = %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z 2 3 4 5 6 7 8 9].freeze

  belongs_to :quiz
  belongs_to :current_question, class_name: "Question", optional: true
  has_many :participations, dependent: :destroy
  has_many :answers, through: :participations

  enum :state, {idle: "idle", running: "running", finished: "finished"}, default: :idle
  enum :question_state, {question: "question", results: "results"}, prefix: :showing

  before_validation :generate_code, on: :create

  validates :code, presence: true, uniqueness: true

  def to_param = code

  def questions = @questions ||= quiz.active_questions.to_a

  def reload(*)
    @questions = nil
    super
  end

  def current_question_number
    current_question && questions.index(current_question)&.+(1)
  end

  def next_question
    list = questions
    return list.first unless current_question

    index = list.index(current_question)
    # The current question may have been deactivated or removed in the meantime
    index ? list[index + 1] : list.find { it.position > current_question.position }
  end

  def last_question? = running? && next_question.nil?

  # When the current question's timer runs out (nil without a timer)
  def question_deadline
    question_started_at + quiz.time_limit if running? && quiz.timer? && question_started_at
  end

  # State transitions are compare-and-set updates, so double clicks and stale
  # moderator screens can't apply the same transition twice.

  def start!
    raise ArgumentError, "Run already started" unless idle?
    first = next_question
    raise ArgumentError, "Quiz has no active questions" unless first

    show_question!(first, from: {state: :idle})
  end

  def close_question!
    return unless running? && showing_question?

    transition!({state: :running, question_state: :question, current_question_id:}, question_state: :results)
  end

  def advance!
    return unless running? && showing_results?

    from = {state: :running, question_state: :results, current_question_id:}
    if (question = next_question)
      show_question!(question, from:)
    else
      transition!(from, state: :finished, question_state: nil)
    end
  end

  def accepting_answers_for?(question)
    running? && showing_question? && current_question_id == question.id
  end

  def leaderboard
    participations.order(score: :desc, correct_time_ms: :asc, created_at: :asc, id: :asc)
  end

  def winners = leaderboard.where(winner: true)

  # Participants with a non-zero score sharing the N-th place score (only
  # meaningful when the line between winners and non-winners isn't clear).
  def cutoff_ties
    contenders = leaderboard.where("score > 0").to_a
    n = quiz.winners_count
    return [] if contenders.size <= n

    cutoff = contenders[n - 1].score
    tied = contenders.select { it.score == cutoff }
    (tied.size > 1 && contenders[n]&.score == cutoff) ? tied : []
  end

  # Picks N winners among participants with a non-zero score. With random: true,
  # anyone strictly above the N-th place score wins outright and the remaining
  # spots are drawn among participants tied at that score (ignoring speed).
  def pick_winners!(random: false)
    raise ArgumentError, "Run is not finished" unless finished?

    contenders = leaderboard.where("score > 0").to_a
    n = quiz.winners_count
    chosen =
      if random && contenders.size > n
        cutoff = contenders[n - 1].score
        sure = contenders.select { it.score > cutoff }
        sure + contenders.select { it.score == cutoff }.sample(n - sure.size)
      else
        contenders.first(n)
      end

    transaction do
      participations.update_all(winner: false)
      participations.where(id: chosen.map(&:id)).update_all(winner: true)
    end
    broadcast_changes
  end

  def reset_winners!
    participations.update_all(winner: false)
    broadcast_changes
  end

  def answers_for(question) = Answer.where(question:, participation: participations)

  # Questions that took part in the run: the active ones plus any answered ones
  # (in case a question was deactivated after the run)
  def asked_questions
    answered_ids = Answer.where(participation: participations).distinct.pluck(:question_id)
    quiz.questions.where(active: true).or(quiz.questions.where(id: answered_ids)).to_a
  end

  # Everyone (participants and moderator screens) re-renders the page
  def broadcast_changes
    broadcast_refresh
    broadcast_refresh_to(self, :moderator)
  end

  private

  def show_question!(question, from:)
    transition!(from, state: :running, current_question_id: question.id, question_state: :question, question_started_at: Time.current)
  end

  def transition!(from, **changes)
    updated = Run.where(id:, **from).update_all(**changes, updated_at: Time.current)
    reload
    broadcast_changes if updated.positive?
    updated.positive?
  end

  def generate_code
    self.code ||= loop do
      candidate = Array.new(5) { CODE_ALPHABET.sample }.join
      break candidate unless Run.exists?(code: candidate)
    end
  end
end
