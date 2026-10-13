# What follows a workflow run's end: its watches stop, and a failure or an all clear is said (WorkflowRunEndService).
# A failure notice the platform did not take is tried again, waiting longer each time, until it lands.
class WorkflowRunEndedJob < ApplicationJob
  queue_as :background

  retry_on AdapterError, wait: :polynomially_longer, attempts: 20

  def perform(run_id)
    run = Workflow::Run.find_by(id: run_id)
    WorkflowRunEndService.new(run).ended! if run&.finished?
  end
end
