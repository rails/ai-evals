class CreateAccountsAndIdentity < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :name, null: false
      t.string :subdomain, null: false
      t.references :owner, type: :uuid
      t.datetime :cancelled_at
      t.timestamps
      t.index :cancelled_at, where: "cancelled_at IS NOT NULL"
    end
    add_index :accounts, :subdomain, unique: true
    create_table :users, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "admin"
      t.boolean :verified, null: false, default: false
      t.boolean :suspended, null: false, default: false
      t.timestamps
    end
    add_index :users, [:account_id, :email], unique: true
    add_foreign_key :accounts, :users, column: :owner_id
    create_table :sessions, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :sessions, :token_digest, unique: true
    create_table :email_tokens, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :purpose, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :email_tokens, :token_digest, unique: true
  end
end
