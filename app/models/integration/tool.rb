# One callable operation on an integration. Enabling it mints exactly one
# tool-kind Ability::Action (key: "<integration_slug>.<name>") — from that
# moment it is grantable, approvable, and ledgered like any other action.
# Vanished/disabled tools keep their action row; the gateway's config check
# stops the calls.
class Integration::Tool < ApplicationRecord
  self.table_name = "integration_tools"

  belongs_to :integration
  has_one :ability_action, class_name: "Ability::Action", as: :source, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :integration_id },
                   format: { with: /\A[a-z0-9_.]+\z/ }

  scope :enabled, -> { where(enabled: true) }

  after_save :sync_ability_action!, if: :saved_change_to_enabled?

  def action_key
    "#{integration.slug}.#{name}"
  end

  def remote_name
    spec["tool_name"].presence || name
  end

  def sync_ability_action!
    return unless enabled?

    action = Ability::Action.find_or_initialize_by(workspace_id: integration.workspace_id, key: action_key)
    action.assign_attributes(
      kind: Ability::Action::KIND_TOOL,
      risk_level: read_only? ? Ability::Action::RISK_READ : Ability::Action::RISK_WRITE,
      reversible: read_only?,
      params_schema: params_schema,
      source: self
    )
    action.save!
    action
  end
end
