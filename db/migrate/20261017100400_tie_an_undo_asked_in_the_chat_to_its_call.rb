# A temporary change with no fixed undo is put back by Halon in the chat. The call it makes to do so is kept on the
# change, so the change counts as undone only once that call runs, and the call is never itself counted down.
class TieAnUndoAskedInTheChatToItsCall < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_mitigations, :undo_tool_call_id, :string
  end
end
