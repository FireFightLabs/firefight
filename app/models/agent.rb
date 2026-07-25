# An AI agent as a first-class principal: it acts with its own grants,
# never the inherited permissions of whoever triggered it. Rows arrive with
# the investigator; the table exists so grants and the ledger never need a
# schema change when it does.
class Agent < ApplicationRecord
  include Principal

  belongs_to :workspace

  has_many :ability_grants, class_name: "Ability::Grant", as: :principal, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id },
                   format: { with: /\A[a-z0-9_]+\z/ }

  scope :active, -> { where(enabled: true, deleted_at: nil) }

  def actor_display_name = name
  def actor_kind = "agent"
  def platform_user_id = nil

  # Agents hold explicit grants — no implicit member-level reads.
  def mcp_readable?(resource)
    Ability::Resolver.resolve(self).covers?(Ability::Action.system_key(resource, ApiKey::ACTION_READ))
  end
end
