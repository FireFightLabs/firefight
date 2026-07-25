class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workspace_id, null: false
      t.string :name, null: false
      t.string :slug, null: false
      t.string :description
      t.boolean :enabled, default: true, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :agents, [ :workspace_id, :slug ], unique: true
    add_foreign_key :agents, :workspaces
  end
end
