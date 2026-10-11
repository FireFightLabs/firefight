# A step that waits for a deploy keeps the deploy live when it began and the version it waits for, so a restart or a
# repair never mistakes the deploy already serving for the new one.
class AddNewDeployToChatWatchSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_watch_steps, :new_deploy, :jsonb
  end
end
