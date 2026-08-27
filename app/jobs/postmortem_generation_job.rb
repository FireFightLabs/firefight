class PostmortemGenerationJob < ApplicationJob
  queue_as :default

  # Transient: retry with backoff, then notify the requester so they aren't
  # left with a silent "generating..." ephemeral that never resolves.
  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.cleanup_in_progress!
    job.notify_failure(error, terminal: false)
  end

  # Terminal: retrying produces the same outcome. Don't burn tokens on retry.
  # Notify and stop.
  discard_on FirefightAi::TerminalError do |job, error|
    job.record_failure(error)
    job.notify_failure(error, terminal: true)
  end

  discard_on ActiveRecord::RecordNotFound

  # The postmortem records who started it, so the job is not told a second time.
  # That copy could only disagree, and it could not name an agent at all.
  def perform(incident_id)
    incident = Incident.find(incident_id)
    return unless incident.postmortem&.generating?

    unless Entitlements.allows?(incident.workspace, Entitlements::AI)
      incident.postmortem.mark_generation_failed!("EntitlementBlocked")
      Rails.logger.info({ event: "postmortem_generation.entitlement_blocked", incident_id: incident_id, workspace_id: incident.workspace_id })
      return
    end

    PostmortemGenerationService.new(incident.workspace).generate!(incident, generated_by: incident.postmortem.generated_by)
  end

  # The placeholder stays, marked failed, so the page can say what happened
  # and offer a retry instead of showing an empty incident.
  def record_failure(error)
    incident_id, = arguments
    postmortem = Incident.find_by(id: incident_id)&.postmortem
    postmortem.mark_generation_failed!(failure_reason(error)) if postmortem&.generating?
  end

  def cleanup_in_progress!
    record_failure(FirefightAi::TransientError.new("retries exhausted"))
  end

  # Whoever asked for it hears that it failed. An agent has no account to be
  # messaged at, so there is nobody to tell and the failure is on the record
  # either way.
  def notify_failure(error, terminal:)
    incident_id, = arguments
    incident = Incident.find_by(id: incident_id)
    author = incident&.postmortem&.generated_by
    return unless incident && incident.channel_id && author&.platform_user_id

    WorkspaceAdapter.for(incident.workspace).post_postmortem_generation_failed(
      channel_id: incident.channel_id,
      user_id: author.platform_user_id,
      incident: incident,
      reason: failure_reason(error),
      retrying: !terminal
    )
  rescue StandardError => e
    Rails.logger.error({
      event: "postmortem_generation.notify_failure_failed",
      incident_id: incident_id,
      error_class: e.class.name,
      error: e.message
    })
  end

  def failure_reason(error)
    error.respond_to?(:reason) ? error.reason : error.class.name.demodulize
  end
end
