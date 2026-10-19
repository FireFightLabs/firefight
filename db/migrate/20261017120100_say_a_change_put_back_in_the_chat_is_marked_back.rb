# A change Halon is asked to put back counts as back once a person marks it, so a note that said only that Halon's call
# asks first now says that too. A note in other words is left as it is.
class SayAChangePutBackInTheChatIsMarkedBack < ActiveRecord::Migration[8.1]
  IN_CHAT = "in_chat".freeze
  OLD_NOTES = [
    "Halon is asked in the chat to put it back, and that call asks first like any change.",
    "Halon puts it back in the chat, and asks first like any change."
  ].freeze
  NOTE = "Halon is asked in the chat to put it back. Its call asks first, and someone marks it once it's back.".freeze

  def up
    execute ActiveRecord::Base.sanitize_sql_array([ "UPDATE chat_mitigations SET undo_note = ?, updated_at = now() WHERE undo_state = ? AND undo_note IN (?)",
                                                    NOTE, IN_CHAT, OLD_NOTES ])
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Which note each change had is not kept."
  end
end
