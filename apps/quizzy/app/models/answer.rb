class Answer < ApplicationRecord
  belongs_to :participation
  belongs_to :question

  validates :question_id, uniqueness: {scope: :participation_id}
  validates :option_index, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validate :option_exists

  # Participants may change their answer until the question is closed
  before_save :evaluate, if: :option_index_changed?
  after_save :update_score, if: :saved_change_to_option_index?
  after_create_commit :broadcast_answers_counter

  private

  def option_exists
    errors.add(:option_index, :invalid) if question && option_index.to_i >= question.options.size
  end

  def evaluate
    run = participation.run
    self.correct = question.correct_option?(option_index)
    self.elapsed_ms = run.question_started_at ? ((Time.current - run.question_started_at) * 1000).round.clamp(0, nil) : 0
  end

  # Recalculated from answers in a single statement to stay consistent when answers change
  def update_score
    Participation.where(id: participation_id).update_all([<<~SQL, id: participation_id])
      score = (SELECT COUNT(*) FROM answers WHERE participation_id = :id AND correct),
      correct_time_ms = (SELECT COALESCE(SUM(elapsed_ms), 0) FROM answers WHERE participation_id = :id AND correct)
    SQL
  end

  def broadcast_answers_counter
    run = participation.run
    broadcast_replace_to [run, :moderator], target: "answers_counter",
      partial: "moderate/runs/answers_counter", locals: {run:, question:}
  end
end
