class AddMatchedRuleToAlerts < ActiveRecord::Migration[8.1]
  def change
    add_reference :alerts, :matched_policy_rule, type: :uuid, null: true,
                  foreign_key: { to_table: :policy_rules, on_delete: :nullify }, index: true
  end
end
