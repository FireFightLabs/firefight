# A message written in the chat platform is saved as the model reads it, with people and channels named and their ids
# kept, and the words as the platform sent them are kept beside it for the pages, which show them as the platform does.
# What a person replied to waits beside their words rather than inside them, so it never shows as theirs. This once
# shared its version with another migration, so a database may already have these columns under that one.
class KeepPlatformWordsBesideTheModelReading < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_messages, :as_written, :text, if_not_exists: true
    add_column :chat_queued_messages, :as_written, :text, if_not_exists: true
    add_column :chat_queued_messages, :context, :text, if_not_exists: true
    add_column :incident_transcript_messages, :model_content, :text, if_not_exists: true
  end
end
