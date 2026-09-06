# The coach in the first test incident's channel. Posts the one step the
# incident has just earned and remembers it on the onboarding row, so every
# entry point (creation, lead, messages, resolve, postmortem) can call this
# and the channel never gets a step twice or a step it has already passed.
class OnboardingWalkthroughService
  def initialize(workspace)
    @workspace = workspace
  end

  # Two callers can arrive together (the close workflow and the resolve
  # event, for one), so the row is read fresh and the step is claimed with a
  # conditional update before anything is posted, and released if the post
  # fails. A canceled incident ends the coaching, there is no postmortem to
  # talk about.
  def advance!(incident)
    onboarding = WorkspaceOnboarding.find_by(workspace: @workspace)
    return { skipped: true } unless onboarding&.tracks?(incident) && incident.channel_id.present? && !incident.canceled?

    seen = onboarding.walkthrough_step
    target = onboarding.stage_of(incident)
    return { skipped: true } if target <= seen.to_i
    return { skipped: true } unless claim(onboarding, from: seen, to: target)

    result = @workspace.adapter.post_first_incident_walkthrough(channel_id: incident.channel_id, incident: incident, step: target)
    { step: target, message_ts: result[:message_id] }
  rescue AdapterError => e
    claim(onboarding, from: target, to: seen)
    Rails.logger.warn({ event: "onboarding_walkthrough.post_failed", incident_id: incident.id, step: target, error: e.message })
    { skipped: true }
  end

  private

  def claim(onboarding, from:, to:)
    WorkspaceOnboarding.where(id: onboarding.id, walkthrough_step: from).update_all(walkthrough_step: to, updated_at: Time.current) > 0
  end
end
