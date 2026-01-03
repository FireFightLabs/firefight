class Workflows::OrchestrateJob < ApplicationJob
  queue_as :workflows

  # Debounced orchestration job
  # Called with 1 second delay to batch multiple orchestration triggers
  def perform(workflow_id)
    workflow = Workflow.find(workflow_id)

    Rails.logger.info({
      event: "workflow.orchestration.started",
      workflow_id: workflow.id,
      workflow_class: workflow.workflow_class,
      current_state: workflow.state
    })

    start_time = Time.current
    workflow.enqueue_next_steps
    duration = Time.current - start_time

    workflow.reload
    Rails.logger.info({
      event: "workflow.orchestration.completed",
      workflow_id: workflow.id,
      workflow_class: workflow.workflow_class,
      new_state: workflow.state,
      duration_seconds: duration.round(3)
    })
  rescue StandardError => e
    Rails.logger.error({
      event: "workflow.orchestration.failed",
      workflow_id: workflow_id,
      error_class: e.class.name,
      error_message: e.message
    })
    raise
  end
end
