# Steps Halon adds to a watch going on the same subject, rather than a second watch. The watch keeps when steps were last
# added, so a check that read the old steps never ends it as done, and whether Halon set its ceiling on reads itself.
class AddAddedStepsToChatWatches < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_watches, :steps_added_at, :datetime
    add_column :chat_watches, :reads_per_hour_asked, :boolean, default: false, null: false
    add_column :chat_watch_steps, :added_at, :datetime
  end
end
