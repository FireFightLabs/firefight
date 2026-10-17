# A change whose undo a model could not write was left to be undone by hand. Halon is now asked in the chat instead, like
# every change no fixed call puts back. One already due by hand waits for a person to mark it back, and is not said to
# be due by hand again.
class MoveUndosByHandToTheChat < ActiveRecord::Migration[8.1]
  BY_HAND = "by_hand".freeze
  IN_CHAT = "in_chat".freeze
  DUE_BY_HAND = "due_by_hand".freeze
  UNDO_ASKED = "undo_asked".freeze
  NOTE = "Halon is asked in the chat to put it back. Its call asks first, and someone marks it once it's back.".freeze

  def up
    execute ActiveRecord::Base.sanitize_sql_array([
      "UPDATE chat_mitigations SET status = ?, claimed_at = now(), reminded_at = now(), updated_at = now() WHERE status = ?", UNDO_ASKED, DUE_BY_HAND
    ])
    execute ActiveRecord::Base.sanitize_sql_array([ "UPDATE chat_mitigations SET undo_state = ?, undo_note = ?, updated_at = now() WHERE undo_state = ?",
                                                    IN_CHAT, NOTE, BY_HAND ])
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Which changes were due by hand is not kept."
  end
end
