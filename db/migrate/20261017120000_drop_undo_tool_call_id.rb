# A change Halon is asked to put back counts as back only when a person marks it, so nothing ties it to Halon's call any
# more.
class DropUndoToolCallId < ActiveRecord::Migration[8.1]
  def change
    remove_column :chat_mitigations, :undo_tool_call_id, :string, if_exists: true
  end
end
