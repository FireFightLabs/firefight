# Runs again every job a stopped worker could not hand back. A worker that stops in time hands its jobs back and Solid
# Queue runs them again. One killed first, or one that died, has its jobs marked failed with a process error, and Solid
# Queue never runs a failed job again. Those are put back here, so an interrupted job runs again whichever way its
# worker stopped, and every job is written to be safe to run again (docs/architecture.md, Deploys).
module InterruptedJob
  # What Solid Queue fails a job with when its worker exited, stopped beating or vanished, and never for the job's own error.
  PROCESS_ERRORS = %w[
    SolidQueue::Processes::ProcessExitError
    SolidQueue::Processes::ProcessPrunedError
    SolidQueue::Processes::ProcessMissingError
  ].freeze

  # A job interrupted this many times is taken to be what stops its worker, such as one that runs it out of memory, and
  # is left failed rather than run forever. Its class is told once, so nobody waits on it.
  GIVE_UP_AFTER = 3

  # Kept on the job's own arguments, so the count survives each run again.
  COUNT = "interruptions".freeze

  def self.run_again!
    return 0 unless SolidQueue::FailedExecution.table_exists?

    process_failures.includes(:job).find_each.count { |failed| run_again(failed) }
  end

  def self.process_failures
    patterns = PROCESS_ERRORS.map { |name| "%\"exception_class\":#{name.to_json}%" }
    SolidQueue::FailedExecution.where(patterns.map { "error LIKE ?" }.join(" OR "), *patterns)
  end

  # True when the job was put back. The count is read and written under the execution's lock, so two sweeps at once
  # put a job back, or give up on it, once.
  def self.run_again(failed)
    job = failed.job
    return false if job.class_name.safe_constantize.try(:runs_again_when_interrupted) == false

    outcome = failed.with_lock do
      job.reload
      count = job.arguments[COUNT].to_i + 1
      next :settled if count > GIVE_UP_AFTER + 1

      job.update!(arguments: job.arguments.merge(COUNT => count))
      next :given_up if count > GIVE_UP_AFTER

      job.prepare_for_execution
      failed.destroy!
      :again
    end
    return false if outcome == :settled

    give_up(job) if outcome == :given_up
    Rails.logger.info({ event: "job.interrupted.#{outcome}", job_class: job.class_name, job_id: job.active_job_id }.to_json)
    outcome == :again
  rescue ActiveRecord::RecordNotFound
    false
  end
  private_class_method :run_again

  def self.give_up(job)
    klass = job.class_name.safe_constantize
    return unless klass.respond_to?(:interrupted_too_often)

    klass.interrupted_too_often(*ActiveJob::Arguments.deserialize(job.arguments["arguments"]))
  rescue ActiveJob::DeserializationError
    nil
  end
  private_class_method :give_up
end
