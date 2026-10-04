# Who writes a fix's code changes. Firefight's own agent does by default, in Firefight's sandbox, through the code host's
# fix_code. An admin can choose a connected coding agent instead under Settings, Workspace, named by its connection's
# slug, which never changes. A code step whose chosen agent cannot run waits for a person rather than falling back to
# Firefight's own agent, since nobody chose that.
module Workspace::CodeFixes
  extend ActiveSupport::Concern

  # The choice that is no connection, as the settings page offers it.
  FIREFIGHT_WRITES = "Firefight's own agent".freeze

  Choice = Data.define(:value, :label)

  included do
    normalizes :code_fix_agent, with: ->(value) { value.to_s.strip.presence }
    validate :code_fix_agent_is_a_coding_agent
  end

  # The connection chosen to write code changes, removed or not, or nil while Firefight's own agent writes them.
  def code_fix_agent_connection
    return if code_fix_agent.blank?

    integrations.find_by(slug: code_fix_agent, provider: IntegrationProvider.coding_agents.map(&:key))
  end

  # The chosen agent's tool that writes a change, while it is switched on and its connection is on.
  def code_fix_agent_tool
    integration = code_fix_agent_connection
    return unless integration

    Integration::Tool.in_workspace(self).find_by(integration_id: integration.id, read_only: false,
                                                 name: IntegrationProvider.find(integration.provider).code_fix_tool)
  end

  # Why code steps cannot reach the chosen agent, or nil when they can or Firefight's own agent writes them.
  def code_fix_agent_blocked_reason
    return if code_fix_agent.blank?

    integration = code_fix_agent_connection
    return "The coding agent chosen to write code fixes was removed, so code steps wait for a person. Choose another one." if integration.nil? || integration.deleted_at
    return "#{integration.name} is turned off, so code steps wait for a person until it is turned on again." if integration.disabled_at
    return "#{integration.name}'s fix_code tool is switched off, so code steps wait for a person. Switch it on under Integrations." unless code_fix_agent_tool

    nil
  end

  # What the settings page offers: Firefight's own agent, then every coding agent connected here.
  def code_fix_agent_choices
    agents = integrations.where(deleted_at: nil, provider: IntegrationProvider.coding_agents.map(&:key)).order(:name)
    [ Choice.new(value: nil, label: FIREFIGHT_WRITES) ] +
      agents.map { |integration| Choice.new(value: integration.slug, label: choice_label(integration)) }
  end

  private

  # A connection named after its provider says it once, and one named otherwise says which agent it is.
  def choice_label(integration)
    provider = IntegrationProvider.find(integration.provider).name
    integration.name == provider ? provider : "#{integration.name} (#{provider})"
  end

  def code_fix_agent_is_a_coding_agent
    return if code_fix_agent.blank? || !will_save_change_to_code_fix_agent?
    return if integrations.where(deleted_at: nil, slug: code_fix_agent, provider: IntegrationProvider.coding_agents.map(&:key)).exists?

    errors.add(:code_fix_agent, "is not a coding agent connected to this workspace")
  end
end
