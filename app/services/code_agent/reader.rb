# What a coding agent in the sandbox reads of the workspace while it writes a change: the tools Halon reads with, as the
# person who asked for the change, through the gateway, each call in Activity under the coding agent. It never changes
# anything, so a tool that changes something is never handed over and nothing waits for a person's confirmation.
class CodeAgent::Reader
  # Where Halon's own tools help with code: what happened, what fired, where things run and what the team wrote down.
  # Permissions, access and setup are about the workspace, never the change.
  FIREFIGHT_GROUPS = [
    Chat::Tools::Groups::INCIDENT_HISTORY, Chat::Tools::Groups::ALERTS, Chat::Tools::Groups::CATALOG, Chat::Tools::Groups::MAP,
    Chat::Tools::Groups::RESOURCES, Chat::Tools::Groups::FOLLOW_UPS, Chat::Tools::Groups::POSTMORTEMS
  ].freeze
  attr_reader :session

  def initialize(session)
    @session = session
  end

  # Every tool the asker may read with, by the name the agent calls it.
  def tools
    @tools ||= Chat::Tools.catalog(self).select { |entry| offered?(entry) }.index_by(&:name)
  end

  # What the shared tools ask of whoever they run for. It reads as the person who asked, changes nothing and keeps nothing.
  def acting_principal = session.principal
  def workspace = session.workspace
  def chat = nil
  def chat_owner = session
  def incident = nil
  def reads_only? = true
  def changes_memory? = false
  def uses_skills? = false
  def code_box_key = session.box_key.presence || "code-agent-#{session.id}"
  def progress_listener(_tool_call_id) = nil
  def confirms?(*, **) = false
  def hold!(*, **) = false
  def mark_step_failed!(_position, _kind) = nil
  def pack_refused!(_action_key, _tool_call_id) = nil

  def refusal(action_key)
    "Not allowed: #{session.principal&.actor_display_name || 'whoever asked for this change'} cannot use #{action_key}. Work from what you can read, and say in your summary what you could not check."
  end

  def tool_call(action_key:, params: {}, scope: {}, approval_id: nil, holdable: true, **, &block)
    raise AbilityGateway::Denied.new(action_key) unless session.principal

    value = Chat::ToolCall.run!(
      workspace: workspace, principal: session.principal, action_key: action_key, params: params, scope: scope,
      context: { source: AbilityGateway::SOURCE_CODE_AGENT, triggered_by_label: session.triggered_by_label, approval_id: approval_id }.compact,
      holdable: holdable, &block
    )
    Chat::ToolCall::Outcome.new(value: value)
  end

  private

  # Ready for the asker and reading only. A tool that can change something is offered only when its guard rewrites every
  # call it makes into a read, as an investigation reads through it.
  def offered?(entry)
    return false unless entry.state == Chat::Tools::STATE_READY && entry.tool
    return FIREFIGHT_GROUPS.include?(entry.group) if entry.source == Chat::Skill::SOURCE_FIREFIGHT && entry.group != Chat::Tools::Groups::RESOURCES

    true
  end
end
