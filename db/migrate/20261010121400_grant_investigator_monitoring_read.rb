# A scheduled check reads what Halon raised before through list_notices, as Firefight's investigator. It holds that
# through an ordinary grant in every workspace, the same one a new workspace gets at install, so an admin can revoke it
# on the Permissions screen.
class GrantInvestigatorMonitoringRead < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      INSERT INTO system_agents (id, slug, name, created_at, updated_at)
      VALUES (gen_random_uuid(), 'investigator', 'Firefight Investigator', now(), now())
      ON CONFLICT (slug) DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO ability_actions (id, key, kind, risk_level, reversible, params_schema, created_at, updated_at)
      VALUES (gen_random_uuid(), 'monitoring.read', 'system', 'read', true, '{}', now(), now())
      ON CONFLICT (key) WHERE workspace_id IS NULL DO NOTHING
    SQL

    execute <<~SQL.squish
      INSERT INTO ability_grants (id, workspace_id, principal_type, principal_id, action_id, scope, created_at, updated_at)
      SELECT gen_random_uuid(), workspaces.id, 'SystemAgent', system_agents.id, ability_actions.id, '{}', now(), now()
      FROM workspaces
      CROSS JOIN system_agents
      CROSS JOIN ability_actions
      WHERE system_agents.slug = 'investigator' AND ability_actions.key = 'monitoring.read' AND ability_actions.workspace_id IS NULL
      ON CONFLICT (workspace_id, principal_type, principal_id, action_id) WHERE action_id IS NOT NULL DO NOTHING
    SQL
  end

  def down
    execute <<~SQL.squish
      DELETE FROM ability_grants
      WHERE action_id IN (SELECT id FROM ability_actions WHERE key = 'monitoring.read' AND workspace_id IS NULL)
        AND principal_type = 'SystemAgent' AND principal_id IN (SELECT id FROM system_agents WHERE slug = 'investigator')
    SQL
  end
end
