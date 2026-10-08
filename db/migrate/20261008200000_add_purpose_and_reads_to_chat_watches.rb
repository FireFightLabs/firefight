class AddPurposeAndReadsToChatWatches < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_watches, :purpose, :text
    add_column :chat_watch_steps, :tool_name, :string
    add_column :chat_watch_steps, :failed_part, :string
    add_column :chat_watch_steps, :failed_part_told_at, :datetime
    add_column :chat_watch_steps, :handed_back_at, :datetime
  end
end
