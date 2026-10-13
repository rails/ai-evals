class AddScoring < ActiveRecord::Migration[8.1]
  def change
    add_column :quizzes, :winners_count, :integer, null: false, default: 3

    add_column :participations, :score, :integer, null: false, default: 0
    add_column :participations, :correct_time_ms, :integer, null: false, default: 0
    add_column :participations, :winner, :boolean, null: false, default: false

    add_column :answers, :elapsed_ms, :integer, null: false, default: 0
  end
end
