class PostmortemGenerationJob < ApplicationJob
  queue_as :default

  # After the retries the requester is told, so they are not left with a
  # "generating..." ephemeral that never resolves.
  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.cleanup_in_progress!
    job.notify_failure(error, terminal: false)
  end

  # Retrying a terminal error produces the same outcome and burns tokens.
  discard_on FirefightAi::TerminalError do |job, error|
    job.record_failure(error)
    job.notify_failure(error, terminal: true)
  end

  discard_on ActiveRecord::RecordNotFound

  # The postmortem records who started it. A copy on the job could only disagree
  # and could not name an agent at all.
  def perform(incident_id)
    incident = Incident.find(incident_id)
    return unless incident.postmortem&.generating?

    unless Entitlements.allows?(incident.workspace, Entitlements::AI)
      incident.postmortem.mark_generation_failed!("EntitlementBlocked")
      Rails.logger.info({ event: "postmortem_generation.entitlement_blocked", incident_id: incident_id, workspace_id: incident.workspace_id })
      return
    end

    PostmortemGenerationService.new(incident.workspace).generate!(incident, generated_by: incident.postmortem.generated_by)
  rescue FirefightAi::TransientError, FirefightAi::TerminalError, ActiveRecord::RecordNotFound
    raise
  rescue StandardError => error
    # Nothing may leave the placeholder in generating.
    record_failure(error)
    notify_failure(error, terminal: true)
    raise
  end

  # The placeholder stays, marked failed, so the page can offer a retry.
  def record_failure(error)
    incident_id, = arguments
    postmortem = Incident.find_by(id: incident_id)&.postmortem
    postmortem.mark_generation_failed!(failure_reason(error)) if postmortem&.generating?
  end

  def cleanup_in_progress!
    record_failure(FirefightAi::TransientError.new("retries exhausted"))
  end

  # An agent has no account to message, the failure is on the record either way.
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
