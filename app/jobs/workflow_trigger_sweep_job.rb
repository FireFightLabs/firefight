# Every minute, starts each workflow whose Schedule or Once at time came (Workflow::ScheduleSweep).
class WorkflowTriggerSweepJob < ApplicationJob
  queue_as :background

  def perform(now = Time.current)
    Workflow::ScheduleSweep.new(now).run!
  end
end
