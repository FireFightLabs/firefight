class CreateChatAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_attachments, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: true
      t.references :chat, type: :uuid, foreign_key: { on_delete: :cascade }, index: true
      t.references :chat_message, type: :uuid, foreign_key: { on_delete: :cascade }, index: true
      t.references :queued_message, type: :uuid, foreign_key: { to_table: :chat_queued_messages, on_delete: :nullify }, index: true
      t.references :uploaded_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }, index: true
      t.references :saved_result, type: :uuid, foreign_key: { to_table: :chat_saved_results, on_delete: :nullify }, index: false
      t.text :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :kind, null: false
      t.text :text
      t.integer :redactions, null: false, default: 0
      t.integer :page_count
      t.integer :position
      t.text :refusal
      t.timestamps
    end
    add_index :chat_attachments, :created_at, where: "chat_id IS NULL", name: "index_chat_attachments_unsent"
  end
end
