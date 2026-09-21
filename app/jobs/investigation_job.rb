class InvestigationJob < ApplicationJob
  GAVE_UP = "Something went wrong on my side".freeze

  queue_as :investigations

  # The run is marked failed only once the retries are gone, so a deadlock or a killed
  # worker resumes rather than burning the run.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.mark_failed(error)
  end

  # Retrying gives the same answer, so the run ends now rather than three attempts later.
  discard_on FirefightAi::TerminalError do |job, error|
    job.mark_failed(error)
  end
  discard_on ActiveRecord::RecordNotFound
  # The worker that holds the lease is already doing this work.
  discard_on Investigation::Runner::LeaseLost

  def perform(investigation_id)
    investigation = Investigation.find(investigation_id)
    return unless investigation.claim!

    work(investigation)
  end

  # The thread is told, or it would show a spinner over a run nobody is working on.
  def mark_failed(error)
    investigation_id, = arguments
    investigation = Investigation.find_by(id: investigation_id)
    return unless investigation&.finish!(status: Investigation::STATUS_FAILED, error_summary: error.class.name)

    Investigation::Delivery.new(investigation).stopped!(GAVE_UP)
  rescue AdapterError => undelivered
    Rails.logger.warn({
      event: "investigation.failure_undelivered", investigation_id: investigation_id, error: undelivered.message
    }.to_json)
  end

  private

  # The retry arrives long before the lease runs out, so an error hands the run back first.
  def work(investigation)
    investigation.build_seed_pack!

    result = Investigation::Runner.new(investigation).run
    investigation.finish!(status: result.status, error_summary: result.error_summary)
  rescue StandardError
    investigation.release!
    raise
  end
end
