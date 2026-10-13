class CreateTeamInvitations < ActiveRecord::Migration[8.1]
  def change
    add_reference :tickets, :assignee, type: :uuid, foreign_key: {to_table: :users}
    create_table :invitations, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :email, null: false
      t.string :role, null: false
      t.string :status, null: false, default: "pending"
      t.string :token_digest
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :invitations, :token_digest, unique: true
    add_index :invitations, [:account_id, :email]
  end
end
