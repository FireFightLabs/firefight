class AddReadingsToChatWatchSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_watch_steps, :readings, :jsonb, default: [], null: false
    add_column :chat_watch_steps, :summary, :text
    add_column :chat_watch_steps, :read_signature, :string
    add_column :chat_watch_steps, :focus, :string
    add_index :chat_watch_steps, :read_signature
  end
end
