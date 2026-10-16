# One way setup's AI step offers Halon its AI (WorkspaceOnboarding#ai_choice_options). The words arrive finished.
class SetupAiChoiceSerializer < BaseSerializer
  object_as :choice

  type WorkspaceOnboarding::AI_CHOICES.map(&:inspect).join(" | ")
  def value
    choice.value
  end

  type :string
  def title
    choice.title
  end

  type :string
  def detail
    choice.detail
  end

  # Why it cannot be chosen yet, or nil.
  type :string, optional: true
  def blocked_reason
    choice.blocked_reason
  end
end
