# A provider skill naming a tool its provider no longer offers, found by the daily check. One row per skill while the
# problem lasts, so whoever runs Firefight sees it until the skill is fixed.
class CreateChatSkillProblems < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_skill_problems, id: :uuid do |t|
      t.string :skill, null: false
      t.string :provider, null: false
      t.jsonb :missing_tools, null: false, default: []
      t.datetime :checked_at, null: false
      t.timestamps
    end
    add_index :chat_skill_problems, :skill, unique: true
  end
end
