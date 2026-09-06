# Keeps the welcome checklist in #incidents in step with the first incident.
# Only the events that can move a step, and only for the incident the
# onboarding tracks, turn into work.
class Onboarding::EventSubscriber
  def self.handle(event)
    return unless WorkspaceOnboarding::PROGRESS_EVENTS.include?(event.event_type)

    incident = Incident.find_by(id: event.incident_id)
    return unless incident

    onboarding = incident.workspace.onboarding
    return unless onboarding&.tracks?(incident)

    WorkspaceOnboardingProgressJob.perform_later(onboarding.id)
  end
end
