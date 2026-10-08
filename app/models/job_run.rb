# A job that must not repeat a change notes that it started, and clears the note when it ends, whether it finished or
# raised. A worker stopped part way never clears it, so the same job starting again finds the note and knows a run of it
# was interrupted. Solid Queue hands a stopped worker's job out again with the same id (docs/architecture.md, Deploys).
class JobRun < ApplicationRecord
  # Notes left by a job that was never run again, kept only this long.
  KEPT_FOR = 7.days

  # When an earlier run of this job started and was interrupted, or nil for a first run.
  def self.start!(job)
    now = Time.current
    inserted = insert_all([ { job_id: job.job_id, job_class: job.class.name, created_at: now } ], unique_by: :job_id, returning: %w[id])
    inserted.rows.any? ? nil : find_by(job_id: job.job_id)&.created_at
  end

  def self.finish!(job) = where(job_id: job.job_id).delete_all

  def self.forget_old! = where(created_at: ...KEPT_FOR.ago).delete_all
end
