class AddTimerToQuizzes < ActiveRecord::Migration[8.1]
  def change
    add_column :quizzes, :timer_minutes, :integer, null: false, default: 0
    add_column :quizzes, :timer_seconds, :integer, null: false, default: 0
  end
end
