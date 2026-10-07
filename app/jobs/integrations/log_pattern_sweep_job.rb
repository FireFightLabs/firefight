module Integrations
  # Once a day, after the baselines, what each resource worth knowing usually logs. Without a workspace it queues a plan
  # per workspace, and with one it works out which connection reads each resource and queues their reads.
  class LogPatternSweepJob < ApplicationJob
    queue_as :background

    def perform(workspace_id = nil)
      return LogPatternSweep.plan!(Workspace.find(workspace_id)) if workspace_id

      LogPatternSweep.queue_all
    end
  end
end
