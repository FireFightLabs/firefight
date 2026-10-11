# A person's direct messages with Halon carry on in one chat across several threads, so each thread the chat was asked
# in is kept and a reply in any of them reaches the same chat.
class CreateConversationThreadLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_thread_links, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :conversation, type: :uuid, null: false, foreign_key: true
      t.string :channel_id, null: false
      t.string :thread_id, null: false
      t.timestamps
    end
    add_index :conversation_thread_links, %i[workspace_id channel_id thread_id], unique: true, name: "index_conversation_thread_links_on_thread"
  end
end
