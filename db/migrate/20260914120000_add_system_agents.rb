# Firefight's own agents. Global, because only the grants differ per tenant.
class AddSystemAgents < ActiveRecord::Migration[8.1]
  def up
    create_table :system_agents, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.string :slug, null: false
      table.string :name, null: false
      table.timestamps
      table.index :slug, unique: true
    end

    execute <<~SQL.squish
      INSERT INTO system_agents (id, slug, name, created_at, updated_at)
      VALUES (gen_random_uuid(), 'investigator', 'Firefight Investigator', now(), now())
    SQL
  end

  def down
    drop_table :system_agents
  end
end
