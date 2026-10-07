# A permission set Firefight keeps in step with a connection's tools, or with every connection's tools that change
# something. A hand-made set has no pack.
class AddPermissionPacksToAbilityRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :ability_roles, :pack, :string
    add_reference :ability_roles, :integration, type: :uuid, foreign_key: { on_delete: :cascade }, index: false
    add_index :ability_roles, [ :integration_id, :pack ], unique: true, where: "integration_id IS NOT NULL",
              name: "index_ability_roles_one_pack_per_connection"
    add_index :ability_roles, [ :workspace_id, :pack ], unique: true, where: "pack IS NOT NULL AND integration_id IS NULL",
              name: "index_ability_roles_one_workspace_pack"
  end
end
