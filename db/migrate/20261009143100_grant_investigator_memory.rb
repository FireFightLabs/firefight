# A run saves what it learns to memory and disputes what a result contradicted through the gateway, as Firefight's
# investigator. It holds both through ordinary grants in every workspace, the same ones a new workspace gets at install,
# so an admin can revoke them on the Permissions screen.
class GrantInvestigatorMemory < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      INSERT INTO system_agents (id, slug, name, created_at, updated_at)
      VALUES (gen_random_uuid(), 'investigator', 'Firefight Investigator', now(), now())
      ON CONFLICT (slug) DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO ability_actions (id, key, kind, risk_level, reversible, params_schema, created_at, updated_at)
      VALUES (gen_random_uuid(), 'memory.create', 'system', 'write', true, '{}', now(), now()),
             (gen_random_uuid(), 'memory.update', 'system', 'write', true, '{}', now(), now())
      ON CONFLICT (key) WHERE workspace_id IS NULL DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO ability_grants (id, workspace_id, principal_type, principal_id, action_id, scope, created_at, updated_at)
      SELECT gen_random_uuid(), workspaces.id, 'SystemAgent', system_agents.id, ability_actions.id, '{}', now(), now()
      FROM workspaces
      CROSS JOIN system_agents
      CROSS JOIN ability_actions
      WHERE system_agents.slug = 'investigator' AND ability_actions.key IN ('memory.create', 'memory.update')
        AND ability_actions.workspace_id IS NULL
      ON CONFLICT (workspace_id, principal_type, principal_id, action_id) WHERE action_id IS NOT NULL DO NOTHING
    SQL
  end

  def down
    execute <<~SQL.squish
      DELETE FROM ability_grants
      WHERE action_id IN (SELECT id FROM ability_actions WHERE key IN ('memory.create', 'memory.update') AND workspace_id IS NULL)
        AND principal_type = 'SystemAgent' AND principal_id IN (SELECT id FROM system_agents WHERE slug = 'investigator')
    SQL
  end
end
