class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

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
