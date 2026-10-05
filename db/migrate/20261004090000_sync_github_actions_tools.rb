# GitHub's pack now reads GitHub Actions (workflow_runs, workflow_jobs, job_log, ci_status), and recent_deployments takes
# a limit. Discovery only runs on connect or refresh, so existing connections get them here. Native packs declare their
# tools locally, so this calls no provider. New rows arrive disabled.
class SyncGithubActionsTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
