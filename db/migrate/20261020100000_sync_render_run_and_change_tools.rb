# Render's pack gained cron_runs, job_runs and task_runs, three reads run history answers through, and twelve changes:
# starting and cancelling runs (trigger_cron_run, cancel_cron_run, cancel_job, run_job, run_task, cancel_task_run), cancel_deploy,
# trigger_deploy, set_autodeploy, set_autoscaling, suspend_service and resume_service. Discovery only runs on connect or
# refresh, so existing connections get them here. Native packs declare their tools locally, so this calls no
# provider.
class SyncRenderRunAndChangeTools < ActiveRecord::Migration[8.1]
  PROVIDER = "render".freeze

  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDER).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
