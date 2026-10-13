class AddTicketPriority < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :priority, :string, null: false, default: "normal"
  end
end
