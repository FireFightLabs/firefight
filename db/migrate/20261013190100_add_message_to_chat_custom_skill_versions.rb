class AddMessageToChatCustomSkillVersions < ActiveRecord::Migration[8.1]
  def change
    change_table :chat_custom_skill_versions, bulk: true do |t|
      t.string :channel_id
      t.string :thread_id
      t.string :message_id
    end
  end
end
