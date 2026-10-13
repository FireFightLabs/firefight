# Holds only the abilities it was granted, never the permissions of whoever
# created it. Tokens rotate, so grants and the ledger attach to the agent.
class Agent < ApplicationRecord
  include Principal

  belongs_to :workspace
  # Plural because rotation mints the new one before revoking the old.
  has_many :api_keys, dependent: :destroy, inverse_of: :agent
  # The workflow whose runs act as it. Such an agent is the workflow's own, so it never holds a token and is managed
  # from the workflow, not from the Agents screen.
  has_one :workflow, inverse_of: :agent, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id },
                   format: { with: /\A[a-z0-9_]+\z/ }

  scope :active, -> { where(enabled: true, deleted_at: nil) }
  scope :ordered, -> { order(:name) }
  # Agents someone made to hold a token, every one but a workflow's own.
  scope :standalone, -> { where.missing(:workflow) }

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
    Ability::Resolver.resolve(self, workspace).covers?(Ability::Action.system_key(resource, Ability::Action::ACTION_READ))
  end
end
