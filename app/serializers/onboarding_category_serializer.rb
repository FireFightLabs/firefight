# One integration category as setup walks through it: what Halon can do with it, whether it must be connected, and
# where each of its providers stands in this workspace.
class OnboardingCategorySerializer < BaseSerializer
  object_as :card

  type :string
  def slug
    card.category.slug
  end

  type :string
  def name
    card.category.name
  end

  type :string
  def tagline
    card.category.tagline
  end

  type :string
  def halon
    card.category.halon
  end

  type :boolean
  def required
    card.category.required
  end

  has_many :rows, serializer: IntegrationCardRowSerializer

  # Why Continue cannot answer it yet, such as nothing connected.
  type :string, optional: true
  def connected_blocked_reason
    WorkspaceOnboarding.category_answer_blocked_reason(card, WorkspaceOnboarding::ANSWER_CONNECTED)
  end

  # Why it cannot be answered with "We don't use this", which a category setup requires says.
  type :string, optional: true
  def unused_blocked_reason
    WorkspaceOnboarding.category_answer_blocked_reason(card, WorkspaceOnboarding::ANSWER_UNUSED)
  end
end
