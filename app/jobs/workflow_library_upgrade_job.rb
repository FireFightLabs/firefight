# Moves every workflow that follows Firefight's library on to the newest version of its item, after a release ships one.
class WorkflowLibraryUpgradeJob < ApplicationJob
  queue_as :background

  def perform
    Workflow::Library.upgrade_all!
  end
end
