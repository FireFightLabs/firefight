# A step of a watch can wait for others to succeed before it is read, a failure is read once more before it ends the
# watch, and a logs step keeps the sources that were already logging before what it waits for began. A line that said
# how a watch ended keeps how it ended, since a reopened watch goes on after it.
class AddOrderToChatWatchSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_watch_steps, :waits_for, :integer, array: true, default: [], null: false
    add_column :chat_watch_steps, :failure_seen_at, :datetime
    add_column :chat_watch_steps, :sources_before, :string, array: true
    add_column :chat_watch_updates, :ended_as, :string
  end
end
