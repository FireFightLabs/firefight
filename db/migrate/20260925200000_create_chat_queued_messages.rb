# What a person sends while the agent is working. It waits here and joins the chat at the agent's next step, since a
# message written straight into the chat could land between a tool call and its result, which a provider refuses.
class CreateChatQueuedMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_queued_messages, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :sender, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.text :content, null: false
      t.datetime :taken_at
      t.timestamps
      t.index :chat_id, where: "taken_at IS NULL", name: "index_chat_queued_messages_waiting"
    end
  end
end
