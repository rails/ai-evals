class Participation < ApplicationRecord
  belongs_to :run
  has_many :answers, dependent: :delete_all

  normalizes :name, with: -> { it.squish }

  validates :name, presence: true, length: {maximum: 40}
  validates :uid, presence: true, uniqueness: {scope: :run_id}

  after_create_commit :broadcast_participants_counter

  def answer_for(question) = answers.find { it.question_id == question.id }

  # Same ordering as Run#leaderboard
  def place
    ahead = run.participations.where("score > :score OR (score = :score AND correct_time_ms < :time) OR " \
      "(score = :score AND correct_time_ms = :time AND (created_at < :created OR (created_at = :created AND id < :id)))",
      score:, time: correct_time_ms, created: created_at, id:)
    ahead.count + 1
  end

  private

  def broadcast_participants_counter
    broadcast_replace_to [run, :moderator], target: "participants_counter",
      partial: "moderate/runs/participants_counter", locals: {run:}
    broadcast_update_to [run, :moderator], target: "lobby_participants_counter", html: run.participations.count.to_s
  end
end
