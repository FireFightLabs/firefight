module Workflow::Orchestratable
  extend ActiveSupport::Concern

  # Main orchestration method
  def enqueue_next_steps
    with_lock("workflow_orchestrate_#{id}") do
      reload
      steps = workflow_steps.reload.to_a

      return if completed? || paused?

      ready = steps.select { |s| s.ready_to_run?(steps) }
      ready = apply_concurrency_limit(steps, ready)

    ready.each do |step|
      step.populate_input!(steps)
      Workflows::RunStepJob.perform_later(step.id)
    end


    update_workflow_state(steps)
    end
  end

  # Schedule with debounce
  def enqueue_next_steps_later
    Workflows::OrchestrateJob.set(wait: 1.second).perform_later(id)
  end


  private

  def apply_concurrency_limit(all_steps, ready_steps)
    max_concurrent = workflow_config.dig("max_concurrent_steps")
    return ready_steps unless max_concurrent

    running_count = all_steps.count(&:running?)
    available_slots = [ max_concurrent - running_count, 0 ].max

    ready_steps.take(available_slots)
  end

  def update_workflow_state(steps)
    if steps.all? { |s| s.succeeded? || s.skipped? }
      update!(state: :succeeded, completed_at: Time.current)
      record_event(WorkflowEvents::Workflow::SUCCEEDED)

    elsif steps.any? { |s| s.failed? && s.attempts >= s.max_attempts }
      update!(state: :failed, completed_at: Time.current)
      record_event(WorkflowEvents::Workflow::FAILED)
    elsif pending?
      update!(state: :running, started_at: Time.current)
    end
  end
end
