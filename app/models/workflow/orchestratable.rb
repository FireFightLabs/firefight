module Workflow::Orchestratable
  extend ActiveSupport::Concern

  # Main orchestration method
  def enqueue_next_steps
    reload
    steps = workflow_steps.reload.to_a

    return if completed? || paused?

    # Build step map for O(1) lookups instead of O(n) array searches
    step_map = steps.index_by(&:name)
    ready = steps.select { |s| s.ready_to_run?(step_map) }
    ready = apply_concurrency_limit(steps, ready)

    # Batch update inputs to avoid N+1 queries
    ready.each do |step|
      step.populate_input_data(steps)
    end

    # Track successfully updated steps for job enqueueing
    successfully_updated = []

    # Batch update all step inputs with optimistic locking
    WorkflowStep.transaction do
      ready.each do |step|
        next unless step.changed?

        # Optimistic locking: only update if status and updated_at haven't changed
        rows_updated = WorkflowStep.where(
          id: step.id,
          status: step.status_was,
          updated_at: step.updated_at_was
        ).update_all(
          input: step.input,
          updated_at: Time.current
        )

        successfully_updated << step if rows_updated > 0
      end
    end

    # Only enqueue jobs for steps that were successfully updated
    successfully_updated.each do |step|
      Workflows::RunStepJob.perform_later(step.id)
    end

    update_workflow_state(steps)
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
    reload # Get fresh state

    if steps.all? { |s| s.succeeded? || s.skipped? }
      # Atomic transition to succeeded with optimistic locking
      current_updated_at = updated_at
      rows_updated = Workflow.where(
        id: id,
        state: [ :pending, :running ],
        updated_at: current_updated_at
      ).update_all(
        state: :succeeded,
        completed_at: Time.current,
        updated_at: Time.current
      )

      if rows_updated > 0
        reload
        record_event(WorkflowEvents::Workflow::SUCCEEDED)
      end

    elsif steps.any? { |s| s.failed? && s.attempts >= s.max_attempts }
      # Atomic transition to failed with optimistic locking
      current_updated_at = updated_at
      rows_updated = Workflow.where(
        id: id,
        state: [ :pending, :running ],
        updated_at: current_updated_at
      ).update_all(
        state: :failed,
        completed_at: Time.current,
        updated_at: Time.current
      )

      if rows_updated > 0
        reload
        record_event(WorkflowEvents::Workflow::FAILED)
      end

    elsif pending?
      # Atomic transition to running with optimistic locking
      current_updated_at = updated_at
      rows_updated = Workflow.where(
        id: id,
        state: :pending,
        updated_at: current_updated_at
      ).update_all(
        state: :running,
        started_at: Time.current,
        updated_at: Time.current
      )

      reload if rows_updated > 0
    end
  end
end
