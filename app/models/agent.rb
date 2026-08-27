# An AI agent as a first-class principal. It takes part in incidents under its
# own name, with only the abilities it was granted, never the permissions of
# whoever created or triggered it. Its tokens are rotatable credentials, so
# grants and the ledger stay attached to the agent rather than to a secret.
class Agent < ApplicationRecord
  include Principal

  belongs_to :workspace
  # Plural because rotation runs two at once, the new one minted and put in
  # place before the old one is revoked.
  has_many :api_keys, dependent: :destroy, inverse_of: :agent

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id },
                   format: { with: /\A[a-z0-9_]+\z/ }

  scope :active, -> { where(enabled: true, deleted_at: nil) }
  scope :ordered, -> { order(:name) }

  # An agent with no live token cannot do anything, which is what the screen
  # says instead of implying it is working.
  def live_api_keys
    api_keys.select(&:live?).sort_by(&:created_at).reverse
  end

  def credentialed?
    live_api_keys.any?
  end

  def last_used_at
    api_keys.filter_map(&:last_used_at).max
  end

  def actor_display_name = name
  def actor_kind = Ability::Principal::KIND_AGENT
  def platform_user_id = nil

  # Agents hold explicit grants, no implicit member-level reads.
  def mcp_readable?(resource)
    Ability::Resolver.resolve(self).covers?(Ability::Action.system_key(resource, Ability::Action::ACTION_READ))
  end
end
