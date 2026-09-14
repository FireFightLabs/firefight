# A principal can be global, so one grant per principal per action was wrong.
# The key is the workspace too, or a global agent could hold one grant across every tenant.
class ScopeAbilityGrantsToAWorkspace < ActiveRecord::Migration[8.1]
  def up
    remove_index :ability_grants, name: "index_ability_grants_on_principal_action"
    remove_index :ability_grants, name: "index_ability_grants_on_principal_role"

    add_index :ability_grants, [ :workspace_id, :principal_type, :principal_id, :action_id ],
              unique: true, name: "index_ability_grants_on_principal_action",
              where: "action_id IS NOT NULL"
    add_index :ability_grants, [ :workspace_id, :principal_type, :principal_id, :role_id ],
              unique: true, name: "index_ability_grants_on_principal_role",
              where: "role_id IS NOT NULL"
  end

  def down
    remove_index :ability_grants, name: "index_ability_grants_on_principal_action"
    remove_index :ability_grants, name: "index_ability_grants_on_principal_role"

    add_index :ability_grants, [ :principal_type, :principal_id, :action_id ],
              unique: true, name: "index_ability_grants_on_principal_action",
              where: "action_id IS NOT NULL"
    add_index :ability_grants, [ :principal_type, :principal_id, :role_id ],
              unique: true, name: "index_ability_grants_on_principal_role",
              where: "role_id IS NOT NULL"
  end
end
