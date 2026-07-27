class BackfillIncidentLeadRoles < ActiveRecord::Migration[8.1]
  # The lead role used to be a code default rendered as an unpersisted row and
  # only written on first assignment. The settings screen now sorts and reorders
  # by id, so every workspace needs a real row.
  def up
    execute <<~SQL
      INSERT INTO incident_roles (id, workspace_id, name, slug, description, position, required, created_at, updated_at)
      SELECT gen_random_uuid(),
             w.id,
             'Incident Lead',
             'incident_lead',
             'Coordinates incident response and makes decisions',
             COALESCE((SELECT MAX(position) FROM incident_roles r WHERE r.workspace_id = w.id), 0) + 1,
             false,
             NOW(),
             NOW()
      FROM workspaces w
      WHERE NOT EXISTS (
        SELECT 1 FROM incident_roles r WHERE r.workspace_id = w.id AND r.slug = 'incident_lead'
      )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
