class CreateChatSavedResults < ActiveRecord::Migration[8.1]
  # A tool result too large to hand the model whole. Kept in full, so the agent reads the parts
  # it needs by line or by search rather than losing whatever did not fit.
  def change
    create_table :chat_saved_results, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: true, index: false
      # What the agent calls it, short enough for a model to say back without a slip.
      t.string :handle, null: false
      t.string :tool_name, null: false
      t.text :content, null: false
      t.integer :line_count, null: false
      t.timestamps
    end
    add_index :chat_saved_results, [ :chat_id, :handle ], unique: true
  end
end
