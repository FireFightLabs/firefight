class CreateAbilityCatalog < ActiveRecord::Migration[8.1]
  def change
    create_table :ability_actions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # workspace_id null = global system action. Tool actions are workspace-scoped
      t.uuid :workspace_id
      t.string :kind, null: false
      t.string :key, null: false
      t.string :risk_level, null: false
      t.boolean :reversible, default: true, null: false
      t.jsonb :params_schema, default: {}, null: false
      t.string :source_type
      t.uuid :source_id

      t.timestamps
    end

    add_index :ability_actions, :key, unique: true, where: "workspace_id IS NULL",
              name: "index_ability_actions_on_system_key"
    add_index :ability_actions, [ :workspace_id, :key ], unique: true, where: "workspace_id IS NOT NULL",
              name: "index_ability_actions_on_workspace_key"
    add_index :ability_actions, [ :source_type, :source_id ]
    add_foreign_key :ability_actions, :workspaces

    create_table :ability_roles, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workspace_id, null: false
      t.string :name, null: false
      t.string :slug, null: false
      t.string :description

      t.timestamps
    end

    add_index :ability_roles, [ :workspace_id, :slug ], unique: true
    add_foreign_key :ability_roles, :workspaces

    create_table :ability_role_actions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :role_id, null: false
      t.uuid :action_id, null: false
      t.jsonb :default_scope, default: {}, null: false

      t.timestamps
    end

    add_index :ability_role_actions, [ :role_id, :action_id ], unique: true
    add_foreign_key :ability_role_actions, :ability_roles, column: :role_id
    add_foreign_key :ability_role_actions, :ability_actions, column: :action_id

    create_table :ability_grants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workspace_id, null: false
      t.string :principal_type, null: false
      t.uuid :principal_id, null: false
      t.uuid :role_id
      t.uuid :action_id
      t.jsonb :scope, default: {}, null: false

      t.timestamps
    end

    add_index :ability_grants, [ :principal_type, :principal_id, :action_id ], unique: true,
              where: "action_id IS NOT NULL", name: "index_ability_grants_on_principal_action"
    add_index :ability_grants, [ :principal_type, :principal_id, :role_id ], unique: true,
              where: "role_id IS NOT NULL", name: "index_ability_grants_on_principal_role"
    add_index :ability_grants, :role_id
    add_index :ability_grants, :action_id
    add_foreign_key :ability_grants, :workspaces
    add_foreign_key :ability_grants, :ability_roles, column: :role_id
    add_foreign_key :ability_grants, :ability_actions, column: :action_id

    add_check_constraint :ability_grants,
                         "(role_id IS NOT NULL AND action_id IS NULL) OR (role_id IS NULL AND action_id IS NOT NULL)",
                         name: "ability_grants_exactly_one_target"
  end
end
