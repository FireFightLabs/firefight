# What Halon may do without asking in any chat, each a risky change an admin chose, through a capability or one
# connection's tool, optionally kept to a connection or an environment.
class CreateAbilityAllowances < ActiveRecord::Migration[8.1]
  def change
    create_table :ability_allowances, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.string :capability
      t.references :action, type: :uuid, foreign_key: { to_table: :ability_actions, on_delete: :cascade }
      t.references :integration, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :environment, type: :uuid, foreign_key: { to_table: :catalog_entries, on_delete: :cascade }
      t.boolean :enabled, default: true, null: false
      t.references :created_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
    end
    add_index :ability_allowances, %i[workspace_id capability action_id integration_id environment_id], unique: true, nulls_not_distinct: true,
                                                                                                       name: "index_ability_allowances_uniquely"
    add_check_constraint :ability_allowances, "(capability IS NULL) <> (action_id IS NULL)", name: "ability_allowances_one_change"
  end
end
