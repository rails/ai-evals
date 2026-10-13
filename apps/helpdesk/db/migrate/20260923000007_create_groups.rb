class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :groups, "account_id, lower(name)", unique: true, name: "groups_account_name_unique"

    create_table :group_memberships, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :group, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.boolean :default, null: false, default: false
      t.timestamps
    end
    add_index :group_memberships, [:group_id, :user_id], unique: true
    add_index :group_memberships, :user_id, unique: true, where: '"default" = TRUE', name: "group_memberships_one_default"

    # Nullable additions preserve existing assignments and both ticket clocks.
    add_reference :tickets, :group, type: :uuid, foreign_key: true
  end
end
