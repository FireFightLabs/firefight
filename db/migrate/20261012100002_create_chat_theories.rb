# The candidate causes Halon weighs while it troubleshoots in a chat, each open, confirmed or ruled out with the evidence
# that settled it. The board is the chat's, rewritten whole each time Halon updates it, and status_changed_at says when a
# theory last moved, so a cause confirmed in a turn is told apart from one confirmed before.
class CreateChatTheories < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_theories, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title, null: false
      t.string :status, null: false
      t.boolean :leading, null: false, default: false
      t.text :evidence
      t.string :tool_call_id
      t.datetime :status_changed_at, null: false
      t.timestamps
    end
    add_index :chat_theories, [ :chat_id, :position ], unique: true
  end
end
