# The coach in the first test incident's channel. Posts the one step the
# incident has just earned and remembers it on the onboarding row, so every
# entry point (creation, lead, messages, resolve, postmortem) can call this
# and the channel never gets a step twice or a step it has already passed.
class OnboardingWalkthroughService
  def initialize(workspace)
    @workspace = workspace
  end

  def advance!(incident)
    onboarding = @workspace.onboarding
    return { skipped: true } unless onboarding&.tracks?(incident) && incident.channel_id.present?

    target = onboarding.walkthrough_target(incident)
    return { skipped: true } if target <= onboarding.walkthrough_step.to_i

    result = @workspace.adapter.post_first_incident_walkthrough(channel_id: incident.channel_id, incident: incident, step: target)
    onboarding.update!(walkthrough_step: target)
    { step: target, message_ts: result[:message_id] }
  rescue AdapterError => e
    Rails.logger.warn({ event: "onboarding_walkthrough.post_failed", incident_id: incident.id, step: target, error: e.message })
    { skipped: true }
  end
end
