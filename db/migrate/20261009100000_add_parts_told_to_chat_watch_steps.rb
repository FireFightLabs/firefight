class AddPartsToldToChatWatchSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_watch_steps, :parts_told, :jsonb, default: {}, null: false
  end
end
