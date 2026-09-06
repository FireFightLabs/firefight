class WorkspaceOnboardingProgressJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(onboarding_id)
    onboarding = WorkspaceOnboarding.find(onboarding_id)
    WorkspaceSetupService.new(onboarding.workspace).refresh_welcome_message(onboarding.workspace)
    incident = onboarding.first_incident
    OnboardingWalkthroughService.new(onboarding.workspace).advance!(incident) if incident
  end
end
