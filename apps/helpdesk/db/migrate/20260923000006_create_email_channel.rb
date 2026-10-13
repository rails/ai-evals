class CreateEmailChannel < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :email_reply_token, :string
    add_index :tickets, :email_reply_token, unique: true
    create_table :inbound_receipts, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.string :message_id_digest, null: false
      t.timestamps
      t.index [:account_id, :message_id_digest], unique: true
    end

    create_table :action_mailbox_inbound_emails do |t|
      t.integer :status, default: 0, null: false
      t.string :message_id, null: false
      t.string :message_checksum, null: false
      t.timestamps
      t.index [:message_id, :message_checksum], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
    end

    create_table :active_storage_blobs do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, precision: 6, null: false
      t.index :key, unique: true
    end
    create_table :active_storage_attachments do |t|
      t.string :name, null: false
      t.references :record, null: false, polymorphic: true, index: false
      t.references :blob, null: false, foreign_key: {to_table: :active_storage_blobs}
      t.datetime :created_at, precision: 6, null: false
      t.index [:record_type, :record_id, :name, :blob_id], name: "index_active_storage_attachments_uniqueness", unique: true
    end
    create_table :active_storage_variant_records do |t|
      t.references :blob, null: false, foreign_key: {to_table: :active_storage_blobs}, index: false
      t.string :variation_digest, null: false
      t.index [:blob_id, :variation_digest], name: "index_active_storage_variant_records_uniqueness", unique: true
    end
  end
end
