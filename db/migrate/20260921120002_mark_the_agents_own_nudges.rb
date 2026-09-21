class MarkTheAgentsOwnNudges < ActiveRecord::Migration[8.1]
  # A nudge is saved as the user's side of the chat, which is how a model reads it. The content is
  # encrypted, so nothing but a column can tell it from what a person said.
  def change
    add_column :chat_messages, :nudge, :boolean, null: false, default: false
  end
end
