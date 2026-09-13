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

    investigation.build_seed_pack!

    # The facts are gathered but nothing reasons over them until the planner exists,
    # and nothing is posted because a briefing with no answer behind it is half a feature.
    # The run says so rather than claiming success or holding the incident's only live slot.
    investigation.finish!(status: Investigation::STATUS_CANCELED, error_summary: "Gathered, nothing to reason with yet")
  end

  def mark_failed(error)
    investigation_id, = arguments
    Investigation.find_by(id: investigation_id)
      &.finish!(status: Investigation::STATUS_FAILED, error_summary: error.class.name)
  end
end
