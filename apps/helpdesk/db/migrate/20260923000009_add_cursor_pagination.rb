class AddCursorPagination < ActiveRecord::Migration[8.1]
  def change
    # PostgreSQL generates independent random key material for old and new
    # businesses. This adds no profile timestamp changes or shared credentials.
    add_column :accounts, :cursor_key, :string, null: false,
      default: -> { "gen_random_uuid()::text || gen_random_uuid()::text" }
    add_index :tickets, [:account_id, :updated_at, :id], name: "tickets_staff_cursor"
    add_index :tickets, [:account_id, :requester_id, :public_updated_at, :id], name: "tickets_customer_cursor"
    add_index :comments, [:ticket_id, :id]
    add_index :comments, [:ticket_id, :public, :id]
    %i[users invitations groups group_memberships].each do |table|
      add_index table, [:account_id, :id]
    end
  end
end
