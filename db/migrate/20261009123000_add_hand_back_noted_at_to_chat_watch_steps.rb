class AddHandBackNotedAtToChatWatchSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_watch_steps, :hand_back_noted_at, :datetime
  end
end
