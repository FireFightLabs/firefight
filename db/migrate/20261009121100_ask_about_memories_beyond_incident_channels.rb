class AskAboutMemoriesBeyondIncidentChannels < ActiveRecord::Migration[8.1]
  def change
    change_column_null :chat_memory_posts, :incident_id, true
    change_column_null :chat_memory_posts, :channel_id, true
    add_reference :chat_memory_posts, :conversation, type: :uuid, foreign_key: { on_delete: :cascade }, index: true
    add_reference :chat_memory_posts, :recipient, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :cascade }, index: true
    add_column :chat_memory_posts, :evidence, :text
    add_check_constraint :chat_memory_posts, "channel_id IS NOT NULL OR conversation_id IS NOT NULL", name: "chat_memory_posts_has_a_place"
  end
end
