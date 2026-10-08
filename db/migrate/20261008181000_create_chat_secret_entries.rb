# A secret a tool call in a chat asked a person to enter, or a credential it made for a person to reveal. The row holds
# where the value goes or comes from, never the value.
class CreateChatSecretEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_secret_entries, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :tool_call_id
      t.string :kind, null: false
      t.references :integration_tool, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.uuid :catalog_entry_id
      t.references :requester, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships, on_delete: :cascade }
      t.string :title, null: false
      t.jsonb :target, null: false, default: {}
      t.string :reference
      t.string :status, null: false
      t.datetime :expires_at
      t.references :done_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :done_at
      t.string :message_channel_id
      t.string :message_id
      t.timestamps
      t.index [ :chat_id, :created_at ]
    end
  end
end
