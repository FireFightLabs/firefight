module Workflow::Orchestratable
  extend ActiveSupport::Concern

  # Main orchestration method
  def enqueue_next_steps
    # Use PostgreSQL advisory lock to prevent concurrent orchestration
    # of the same workflow (e.g., multiple OrchestrateJobs running at once)
    lock_key = advisory_lock_key

    ApplicationRecord.connection.execute("SELECT pg_advisory_lock(#{lock_key.to_i})")

    begin
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
    ensure
      # Always release the advisory lock
      ApplicationRecord.connection.execute("SELECT pg_advisory_unlock(#{lock_key.to_i})")
    end
  end

  # Schedule with debounce
  def enqueue_next_steps_later
    Workflows::OrchestrateJob.set(wait: 1.second).perform_later(id)
  end


  private

  # Generate a unique advisory lock key for this workflow
  # PostgreSQL advisory locks use bigint (8 bytes), so we hash the UUID
  def advisory_lock_key
    # Convert UUID to a consistent integer for advisory lock
    # Use CRC32 for a simple hash that fits in PostgreSQL's bigint
    Zlib.crc32("workflow_orchestrate_#{id}")
  end

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
