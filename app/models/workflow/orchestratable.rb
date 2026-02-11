module Workflow::Orchestratable
  extend ActiveSupport::Concern

  # Main orchestration method
  def enqueue_next_steps
    reload
    steps = workflow_steps.reload.to_a

    Rails.logger.info({
      event: "workflow.orchestration.debug_start",
      workflow_id: id,
      workflow_state: state,
      completed: completed?,
      paused: paused?,
      steps_count: steps.count
    })

    return if completed? || paused?

    # Build step map for O(1) lookups instead of O(n) array searches
    step_map = steps.index_by(&:name)
    ready = steps.select { |s| s.ready_to_run?(step_map) }
    ready = apply_concurrency_limit(steps, ready)

    Rails.logger.info({
      event: "workflow.orchestration.debug_ready",
      workflow_id: id,
      ready_count: ready.count,
      ready_steps: ready.map(&:name)
    })

    # Batch update inputs to avoid N+1 queries
    ready.each do |step|
      step.populate_input_data(steps, step_map: step_map)
    end

    # Batch update step inputs with optimistic locking (only for steps with dependencies)
    WorkflowStep.transaction do
      ready.each do |step|
        next unless step.changed?

        # Optimistic locking: only update if status and updated_at haven't changed
        WorkflowStep.where(
          id: step.id,
          status: step.status_was,
          updated_at: step.updated_at_was
        ).update_all(
          input: step.input,
          updated_at: Time.current
        )
      end
    end

    # Enqueue jobs for all ready steps
    Rails.logger.info({
      event: "workflow.orchestration.debug_enqueue",
      workflow_id: id,
      enqueueing_count: ready.count
    })

    ready.each do |step|
      Rails.logger.info({
        event: "workflow.orchestration.debug_enqueue_step",
        workflow_id: id,
        step_id: step.id,
        step_name: step.name
      })
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
      current_time = Time.current
      # Atomic transition to succeeded with optimistic locking
      current_updated_at = updated_at
      rows_updated = Workflow.where(
        id: id,
        state: [ :pending, :running ],
        updated_at: current_updated_at
      ).update_all(
        state: :succeeded,
        completed_at: current_time,
        updated_at: current_time,
        state_timestamps: state_timestamps_merge_sql("succeeded", current_time)
      )

      if rows_updated > 0
        reload
        record_event(WorkflowEvents::Workflow::SUCCEEDED)
      end

    elsif steps.any? { |s| s.failed? && s.attempts >= s.max_attempts }
      current_time = Time.current
      # Atomic transition to failed with optimistic locking
      current_updated_at = updated_at
      rows_updated = Workflow.where(
        id: id,
        state: [ :pending, :running ],
        updated_at: current_updated_at
      ).update_all(
        state: :failed,
        completed_at: current_time,
        updated_at: current_time,
        state_timestamps: state_timestamps_merge_sql("failed", current_time)
      )

      if rows_updated > 0
        reload
        record_event(WorkflowEvents::Workflow::FAILED)
      end

    elsif pending?
      current_time = Time.current
      # Atomic transition to running with optimistic locking
      current_updated_at = updated_at
      rows_updated = Workflow.where(
        id: id,
        state: :pending,
        updated_at: current_updated_at
      ).update_all(
        state: :running,
        started_at: current_time,
        updated_at: current_time,
        state_timestamps: state_timestamps_merge_sql("running", current_time)
      )

      reload if rows_updated > 0
    end
  end

  def state_timestamps_merge_sql(state, timestamp)
    state_value = Workflow.connection.quote(state.to_s)
    timestamp_value = Workflow.connection.quote(timestamp.iso8601)
    Arel.sql("coalesce(state_timestamps, '{}'::jsonb) || jsonb_build_object(#{state_value}, #{timestamp_value})")
  end
end
