class InvestigationJob < ApplicationJob
  queue_as :investigations

  # The run is marked failed only once the retries are gone, so a deadlock or a killed
  # worker resumes rather than burning the run.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.mark_failed(error)
  end

  discard_on ActiveRecord::RecordNotFound
  # The worker that holds the lease is already doing this work.
  discard_on InvestigationRunner::LeaseLost

  def perform(investigation_id)
    investigation = Investigation.find(investigation_id)
    return unless investigation.claim!

    investigation.build_seed_pack! if investigation.seed_pack.blank?

    result = InvestigationRunner.new(investigation).run
    investigation.finish!(status: result.status, error_summary: result.error_summary)
  end

  def mark_failed(error)
    investigation_id, = arguments
    Investigation.find_by(id: investigation_id)
      &.finish!(status: Investigation::STATUS_FAILED, error_summary: error.class.name)
  end
end
