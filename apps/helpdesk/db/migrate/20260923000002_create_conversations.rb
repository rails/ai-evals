class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :tickets, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :requester, type: :uuid, null: false, foreign_key: {to_table: :users}
      t.string :subject, null: false
      t.string :status, null: false, default: "open"
      t.datetime :public_updated_at, null: false
      t.timestamps
    end
    create_table :comments, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :ticket, type: :uuid, null: false, foreign_key: true
      t.references :author, type: :uuid, null: false, foreign_key: {to_table: :users}
      t.text :body, null: false
      t.boolean :public, null: false, default: true
      t.timestamps
    end
  end
end
