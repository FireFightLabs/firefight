# What a chat step that runs long, a coding agent writing a change, has done so far, so a reload or a second viewer sees
# the same steps as whoever watched them arrive.
class CreateChatStepProgresses < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_step_progresses, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :tool_call_id, null: false
      t.text :progress, null: false
      t.timestamps
    end
    add_index :chat_step_progresses, [ :chat_id, :tool_call_id ], unique: true
  end
end
