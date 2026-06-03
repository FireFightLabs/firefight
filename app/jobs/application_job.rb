class ApplicationJob < ActiveJob::Base
  # Transient DB-level errors that should retry rather than fail the job.
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # A job referencing a record that no longer exists has nothing to do; retrying
  # it just wastes attempts and pollutes logs.
  discard_on ActiveJob::DeserializationError

  def serialize
    super.merge("trace_id" => Current.trace_id)
  end

  def deserialize(job_data)
    super
    @trace_id = job_data["trace_id"]
  end

  def trace_id
    @trace_id
  end

  around_perform do |job, block|
    if job.trace_id.present?
      logger.tagged(trace_id: job.trace_id) { block.call }
    else
      block.call
    end
  end
end
