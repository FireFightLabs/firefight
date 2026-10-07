# Every workspace that already went through the old onboarding connected Slack, which was all it asked. Those are done,
# so nobody already using Firefight is sent through the new checklist. A workspace started without Slack is still new.
class FinishChecklistForConnectedWorkspaces < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE workspace_onboardings SET checklist_completed_at = now()
      WHERE checklist_completed_at IS NULL
        AND workspace_id IN (SELECT id FROM workspaces WHERE platform IS NOT NULL)
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
