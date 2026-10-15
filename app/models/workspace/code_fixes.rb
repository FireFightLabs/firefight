# Who writes a fix's code changes. Firefight's own agent does by default, in Firefight's sandbox, through the code host's
# fix_code. An admin can choose a connected coding agent instead under Settings, Workspace, named by its connection's
# slug, which never changes. A code step whose chosen agent cannot run waits for a person rather than falling back to
# Firefight's own agent, since nobody chose that. An admin also sets what Firefight's own agent may spend on one fix.
module Workspace::CodeFixes
  extend ActiveSupport::Concern

  # The choice that is no connection, as the settings page offers it.
  FIREFIGHT_WRITES = "Firefight's own agent".freeze

  Choice = Data.define(:value, :label)

  # What one code fix may spend on its model calls and its review before it pauses for Continue, in cents so dollars
  # are only the display. Less than the least buys a change too few calls to finish anything.
  DEFAULT_CODE_FIX_BUDGET_CENTS = 200
  MIN_CODE_FIX_BUDGET_CENTS = 50
  MAX_CODE_FIX_BUDGET_CENTS = 5_000
  CODE_FIX_BUDGET_RANGE = "A code fix's budget must be between $0.50 and $50.".freeze

  included do
    normalizes :code_fix_agent, with: ->(value) { value.to_s.strip.presence }
    validate :code_fix_agent_is_a_coding_agent
    validates :code_fix_budget_cents, numericality: { only_integer: true, greater_than_or_equal_to: MIN_CODE_FIX_BUDGET_CENTS,
                                                      less_than_or_equal_to: MAX_CODE_FIX_BUDGET_CENTS, message: CODE_FIX_BUDGET_RANGE }
  end

  def code_fix_budget_micros = code_fix_budget_cents * FirefightAi::AgentLoop::MICROS_PER_CENT

  def shown_code_fix_budget = CodeAgentSession.dollars(code_fix_budget_micros)

  # The connection chosen to write code changes, removed or not, or nil while Firefight's own agent writes them.
  def code_fix_agent_connection
    return if code_fix_agent.blank?

    integrations.find_by(slug: code_fix_agent, provider: IntegrationProvider.coding_agents.map(&:key))
  end

  # The chosen agent's tool that writes a change, while it is switched on and its connection is on.
  def code_fix_agent_tool
    integration = code_fix_agent_connection
    return unless integration

    tool_name = IntegrationProvider.find(integration.provider).code_fix_tool
    switched_on_tools.find { |tool| tool.integration_id == integration.id && !tool.read_only? && tool.name == tool_name }
  end

  # Why code steps cannot reach the chosen agent, or nil when they can or Firefight's own agent writes them.
  def code_fix_agent_blocked_reason
    return if code_fix_agent.blank?

    integration = code_fix_agent_connection
    return "The coding agent chosen to write code fixes was removed, so code steps wait for a person. Choose another one." if integration.nil? || integration.deleted_at
    return "#{integration.name} is switched off, so code steps wait for a person until it is switched on again." if integration.disabled_at
    return "#{integration.name}'s fix_code tool is switched off, so code steps wait for a person. Switch it on under Integrations." unless code_fix_agent_tool

    nil
  end

  # What the settings page offers: Firefight's own agent, then every coding agent connected here.
  def code_fix_agent_choices
    agents = integrations.where(deleted_at: nil, provider: IntegrationProvider.coding_agents.map(&:key)).order(:name)
    [ Choice.new(value: nil, label: FIREFIGHT_WRITES) ] +
      agents.map { |integration| Choice.new(value: integration.slug, label: integration.display_name) }
  end

  private

  def code_fix_agent_is_a_coding_agent
    return if code_fix_agent.blank? || !will_save_change_to_code_fix_agent?
    return if integrations.where(deleted_at: nil, slug: code_fix_agent, provider: IntegrationProvider.coding_agents.map(&:key)).exists?

    errors.add(:code_fix_agent, "is not a coding agent connected to this workspace")
  end
end
