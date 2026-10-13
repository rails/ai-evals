class CreateParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :participations do |t|
      t.references :run, null: false, foreign_key: true
      t.string :uid, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :participations, [:run_id, :uid], unique: true
  end
end
