class InvestigationJob < ApplicationJob
  GAVE_UP = "Something went wrong on my side".freeze
  # Kept on the run for whoever debugs it.
  TOO_MANY_ATTEMPTS = "TooManyAttempts".freeze

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
    return unless investigation.claim!(by: job_id)
    return give_up(investigation, TOO_MANY_ATTEMPTS) if investigation.worn_out?

    work(investigation)
  end

  # The thread is told, or it would show a spinner over a run nobody is working on. The precise
  # cause stays on the run for whoever debugs it and is never said to the people in the thread.
  def mark_failed(error)
    investigation_id, = arguments
    investigation = Investigation.find_by(id: investigation_id)
    give_up(investigation, error.try(:reason) || error.class.name) if investigation
  end

  private

  def give_up(investigation, cause)
    return unless investigation.finish!(status: Investigation::STATUS_FAILED, error_summary: cause)

    Integrations::CodeReading.close(investigation.code_box_key)
    Investigation::Delivery.new(investigation).stopped!(GAVE_UP, rerunnable: true)
  rescue AdapterError => undelivered
    Rails.logger.warn({
      event: "investigation.failure_undelivered", investigation_id: investigation.id, error: undelivered.message
    }.to_json)
  end

  # The retry arrives long before the lease runs out, so an error hands the run back first.
  def work(investigation)
    investigation.build_seed_pack!
    Investigation::WhatChanged.new(investigation).note!

    result = Investigation::Runner.new(investigation).run
    investigation.finish!(status: result.status, error_summary: result.error_summary)
    # Nothing reads code once the run is over, and a box costs while it runs. A retry keeps it, since it reads there again.
    Integrations::CodeReading.close(investigation.code_box_key)
  rescue StandardError
    investigation.release!
    raise
  end
end
