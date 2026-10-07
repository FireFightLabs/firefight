# A member refused a change asks the workspace admins for the pack that would allow it, at most once a day. A chat that
# was refused keeps a card with the ask, posted in its Slack thread too.
class CreatePackRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :ability_pack_requests, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :requester, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships, on_delete: :cascade }, index: false
      t.references :role, type: :uuid, null: false, foreign_key: { to_table: :ability_roles, on_delete: :cascade }
      t.datetime :requested_at
      t.datetime :given_at
      t.references :given_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }, index: false
      t.datetime :dismissed_at
      t.jsonb :notifications, null: false, default: []
      t.timestamps
    end
    add_index :ability_pack_requests, [ :requester_id, :role_id ], unique: true
    add_index :ability_pack_requests, [ :workspace_id, :requested_at ]

    create_table :chat_pack_refusals, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :pack_request, type: :uuid, null: false, foreign_key: { to_table: :ability_pack_requests, on_delete: :cascade }
      t.string :tool_call_id
      t.string :message_channel_id
      t.string :message_id
      t.timestamps
    end
    add_index :chat_pack_refusals, [ :chat_id, :pack_request_id ], unique: true
  end
end
