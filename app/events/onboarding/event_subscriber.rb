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
