class LetChatStepProgressRepeatCallIds < ActiveRecord::Migration[8.1]
  def change
    remove_index :chat_step_progresses, [ :chat_id, :tool_call_id ], unique: true
    add_index :chat_step_progresses, [ :chat_id, :tool_call_id, :created_at ], name: "index_chat_step_progresses_on_call_and_time"
  end
end
