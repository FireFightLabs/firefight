# Drops the details of workflow runs past each workspace's retention, keeping each run's one line for good.
class WorkflowRunRetentionJob < ApplicationJob
  queue_as :background

  def perform
    Workspace.where(id: Workflow::Run.select(:workspace_id).where(details_pruned_at: nil)).find_each do |workspace|
      pruned = Workflow::Run.prune_details!(workspace)
      Rails.logger.info({ event: "workflow_run_retention.pruned", workspace_id: workspace.id, runs: pruned }) if pruned.positive?
    end
  end
end
