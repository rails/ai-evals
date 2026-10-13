class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.references :quiz, null: false, foreign_key: true
      t.string :code, null: false, index: {unique: true}
      t.string :state, null: false, default: "idle"
      t.references :current_question, foreign_key: {to_table: :questions, on_delete: :nullify}
      t.string :question_state
      t.datetime :question_started_at, precision: 6

      t.timestamps
    end
  end
end
