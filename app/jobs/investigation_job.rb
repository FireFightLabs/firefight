class InvestigationJob < ApplicationJob
  queue_as :investigations

  # The run is marked failed only once the retries are gone, so a deadlock or a killed
  # worker resumes rather than burning the run.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.mark_failed(error)
  end

  discard_on ActiveRecord::RecordNotFound

  def perform(investigation_id)
    investigation = Investigation.find(investigation_id)
    return unless investigation.claim!

    # Nothing to run until the planner exists. The run says so rather than claiming
    # success or holding the incident's only live slot.
    investigation.finish!(status: Investigation::STATUS_CANCELED, error_summary: "Nothing to run yet")
  end

  def mark_failed(error)
    investigation_id, = arguments
    Investigation.find_by(id: investigation_id)
      &.finish!(status: Investigation::STATUS_FAILED, error_summary: error.class.name)
  end
end
