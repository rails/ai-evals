class CreateAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :answers do |t|
      t.references :participation, null: false, foreign_key: true, index: false
      t.references :question, null: false, foreign_key: true
      t.integer :option_index, null: false
      t.boolean :correct, null: false, default: false

      t.timestamps
    end

    add_index :answers, [:participation_id, :question_id], unique: true
  end
end
