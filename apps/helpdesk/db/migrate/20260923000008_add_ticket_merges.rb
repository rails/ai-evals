class AddTicketMerges < ActiveRecord::Migration[8.1]
  def change
    # Existing conversations retain their data and both timestamps.
    add_reference :tickets, :merged_into, type: :uuid, foreign_key: {to_table: :tickets}
    add_check_constraint :tickets,
      "(status = 'closed' AND merged_into_id IS NOT NULL) OR (status <> 'closed' AND merged_into_id IS NULL)",
      name: "tickets_closed_requires_merge"
    add_check_constraint :tickets, "merged_into_id <> id", name: "tickets_cannot_merge_into_self"
  end
end
