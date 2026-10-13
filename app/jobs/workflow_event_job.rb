# Hears something that happened for the workspace's workflows (Workflow::Trigger::Events) and starts every one it matches.
# A record deleted before the job ran is let go, since there is nothing left to start a run about.
class WorkflowEventJob < ApplicationJob
  queue_as :events

  discard_on ActiveJob::DeserializationError

  def perform(workspace_id, kind, key, subject, details = {}, actor = nil)
    workspace = Workspace.find_by(id: workspace_id)
    return unless workspace

    WorkflowTriggerService.new(workspace).heard!(kind, key: key, subject: subject, details: details, actor: actor)
  end
end
