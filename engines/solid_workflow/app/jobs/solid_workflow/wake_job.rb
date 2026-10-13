module SolidWorkflow
  # Wakes a parked step at the time it asked for. The sweeper wakes any whose job was lost.
  class WakeJob < ActiveJob::Base
    queue_as { SolidWorkflow.queue_name }

    def perform(step_id)
      step = SolidWorkflow::Step.find_by(id: step_id)
      return unless step&.workflow&.runnable?

      step.wake_if_due!
    end
  end
end
