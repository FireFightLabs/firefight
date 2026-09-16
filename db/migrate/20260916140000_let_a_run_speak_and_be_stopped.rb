class LetARunSpeakAndBeStopped < ActiveRecord::Migration[8.1]
  def change
    # The thread the run posts in, and the one Slack scopes its agent session to.
    add_column :investigations, :thread_id, :string
    # Set when someone presses stop. The worker notices and ends the run.
    add_column :investigations, :cancel_requested, :boolean, null: false, default: false
  end
end
