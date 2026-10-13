class Quiz < ApplicationRecord
  include Portable

  has_many :questions, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :quiz
  has_many :runs, -> { order(id: :desc) }, dependent: :destroy, inverse_of: :quiz

  validates :title, presence: true
  validates :winners_count, numericality: {only_integer: true, greater_than: 0}
  validates :timer_minutes, :timer_seconds, numericality: {only_integer: true, in: 0..59}

  def active_questions = questions.active

  # Seconds per question; 0 means no timer
  def time_limit = timer_minutes * 60 + timer_seconds

  def timer? = time_limit.positive?

  def timer_label = format("%d:%02d", timer_minutes, timer_seconds)
end
