# enabled is the admin's allowlist, removed_at is whether the provider still offers it.
# Discovery only writes removed_at, so a tool that vanishes and returns keeps the admin's choice.
class Integration::Tool < ApplicationRecord
  belongs_to :integration
  has_one :ability_action, class_name: "Ability::Action", as: :source, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :integration_id },
                   format: { with: /\A[a-z0-9_.]+\z/ }

  scope :enabled, -> { where(enabled: true) }
  scope :available, -> { where(removed_at: nil) }
  scope :in_workspace, ->(workspace) {
    enabled.available.joins(:integration)
      .where(integrations: { workspace_id: workspace.id, disabled_at: nil, deleted_at: nil })
      .includes(:integration, :ability_action)
  }

  # Synced on every mirrored attribute, a stale risk_level on the action
  # would silently stop risk-based approval policies from matching.
  after_save :sync_ability_action!, if: :ability_action_stale?

  def action_key
    "#{integration.slug}.#{name}"
  end

  # A tool name cannot carry the dot an action key separates on.
  def model_facing_name
    action_key.tr(".", "_")
  end

  # Whether it is worth offering. Each call is still authorized on its own.
  def callable_by?(principal, resolved = Ability::Resolver.resolve(principal, integration.workspace))
    return true if resolved.action_keys.include?(action_key)

    ability_action.present? && principal.implicitly_allowed?(ability_action)
  end

  def available?
    removed_at.nil?
  end

  def toggle_blocked_reason
    return if available?

    "The provider no longer offers this capability. Refresh the tools to check again."
  end

  def configured_for?(scope)
    return false unless enabled? && available? && integration.operational?

    integration.resolve_environment(scope["environment"] || scope[:environment]).present?
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

  private

  def ability_action_stale?
    saved_change_to_enabled? || saved_change_to_read_only? || saved_change_to_params_schema?
  end
end
