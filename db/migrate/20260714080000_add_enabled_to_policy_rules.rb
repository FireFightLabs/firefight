class AddEnabledToPolicyRules < ActiveRecord::Migration[8.1]
  def change
    add_column :policy_rules, :enabled, :boolean, null: false, default: true
  end
end
