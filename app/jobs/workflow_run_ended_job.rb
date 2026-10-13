# What follows a workflow run's end: its watches stop, and a failure or an all clear is said (WorkflowRunEndService).
class WorkflowRunEndedJob < ApplicationJob
  queue_as :background

  def perform(run_id)
    run = Workflow::Run.find_by(id: run_id)
    WorkflowRunEndService.new(run).ended! if run&.finished?
  end
end
