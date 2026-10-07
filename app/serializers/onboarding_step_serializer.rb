# One step of the setup checklist and where it stands. The checklist decides the state, never the page.
class OnboardingStepSerializer < BaseSerializer
  object_as :step

  type WorkspaceOnboarding::CHECKLIST_STEPS.map(&:inspect).join(" | ")
  def key
    step.key
  end

  type WorkspaceOnboarding::STATES.map(&:inspect).join(" | ")
  def state
    step.state
  end

  # Done or skipped, so it no longer holds setup up.
  type :boolean
  def finished
    step.finished?
  end

  # Why a step cannot be taken yet, or why this workspace skips it.
  type :string, optional: true
  def note
    step.note
  end
end
