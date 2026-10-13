class AddEnabledToChatCustomSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :chat_custom_skills, :enabled, :boolean, null: false, default: true
  end
end
