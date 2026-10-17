# A model no longer writes the undo of a temporary change. A change still waiting for one when that stopped, whose job
# may never run, is put back in the chat instead, the same as one that never had a fixed undo.
class MoveUnwrittenUndosToTheChat < ActiveRecord::Migration[8.1]
  WRITING = "writing".freeze
  IN_CHAT = "in_chat".freeze
  NOTE = "Halon is asked in the chat to put it back, its call asks first, and it is marked back once it is.".freeze

  def up
    execute ActiveRecord::Base.sanitize_sql_array([ "UPDATE chat_mitigations SET undo_state = ?, undo_note = ?, updated_at = now() WHERE undo_state = ?",
                                                    IN_CHAT, NOTE, WRITING ])
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Which changes were waiting for a written undo is not kept."
  end
end
