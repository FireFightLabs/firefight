class ApplicationJob < ActiveJob::Base
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # A job whose record no longer exists has nothing to do.
  discard_on ActiveJob::DeserializationError

  # When an earlier run of this job was stopped part way, by a deploy or a crash, or nil. Set only for a job that calls
  # notices_interruptions.
  attr_accessor :interrupted_at

  # For a job that must not repeat a change. The note is cleared when the job finishes or raises, never when its thread
  # is killed, so only a worker stopped mid run leaves it for the same job to find.
  def self.notices_interruptions
    around_perform do |job, block|
      job.interrupted_at = JobRun.start!(job)
      begin
        block.call
      rescue StandardError
        JobRun.finish!(job)
        raise
      end
      JobRun.finish!(job)
    end
  end

  # Whether InterruptedJob puts the job back when its worker was killed. Off for a job whose own recovery decides.
  class_attribute :runs_again_when_interrupted, default: true

  # Called once a job was interrupted InterruptedJob::GIVE_UP_AFTER times, with its arguments, so whoever waits on it
  # is told it ended. Most jobs leave nothing waiting.
  def self.interrupted_too_often(*) = nil

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
