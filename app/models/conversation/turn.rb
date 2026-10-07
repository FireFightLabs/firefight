# Tool calls act as the person who asked, so a chat reaches exactly what they can in the dashboard.
class Conversation::Turn
  attr_reader :conversation, :asker

  delegate :workspace, :incident, :chat, :code_box_key, to: :conversation

  def initialize(conversation, asker:)
    @conversation = conversation
    @asker = asker
  end

  def acting_principal = asker

  # A chat may change things, each one confirmed by the person who asked.
  def reads_only? = false

  def changes_memory? = true

  # A turn's chat with the model is its conversation's.
  def chat_owner = conversation

  # A turn nobody can be credited with does nothing.
  def tool_call(action_key:, params: {}, scope: {}, approval_id: nil, **, &block)
    raise AbilityGateway::Denied.new(action_key) unless asker

    value = Chat::ToolCall.run!(
      workspace: workspace, principal: asker, action_key: action_key, params: params, scope: scope,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: conversation.incident_id, approval_id: approval_id }.compact,
      &block
    )
    Chat::ToolCall::Outcome.new(value: value)
  end

  # A chat keeps no steps of its own, its tool calls carry how they went.
  def mark_step_failed!(_position, _kind) = nil

  # Only destructive or irreversible changes wait, plus those an approval rule lets the asker approve themselves, and a
  # tool that declares itself destructive. A tool the person allowed for the rest of the chat stops asking, except where
  # an approval rule applies, since that rule wants each call signed off.
  def confirms?(action, tool_name: nil, declared_destructive: false)
    return false unless asker
    return true if action && self_approvable?(action)
    return false if chat&.allows_tool?(tool_name)

    declared_destructive || (action.present? && (action.risk_level == Ability::Action::RISK_DESTRUCTIVE || !action.reversible))
  end

  # A call an approval rule held for someone else's approval is kept with the chat, so once approved the person who asked
  # is asked here whether to run it. An outside agent's chat has nobody to ask, so its calls are not kept.
  def hold!(approval, tool_name:, tool_call_id:, target: nil)
    return false if conversation.mcp? || chat.nil?

    Chat::HeldCall.hold!(chat: chat, approval: approval, tool_name: tool_name, tool_call_id: tool_call_id, target: target)
    true
  end

  # A change to memory in a chat is the asker's, so it goes through the gateway and the ledger like any tool call.
  # Returns what the block returns.
  def memory_change(crud_action, params:, tool_name:, &)
    tool_call(action_key: Ability::Action.system_key(Ability::Action::RESOURCE_MEMORY, crud_action), params: params,
              tool_name: tool_name, label: nil, &).value
  end

  # Where what the agent remembers came from, and who taught it.
  def memory_source = conversation

  def memory_teacher = asker

  def refusal(action_key)
    "Not allowed: #{asker_name} cannot use #{action_key} in this workspace. Tell them, and that a workspace admin can grant it."
  end

  # Starting a run spends money and posts in the channel, so it goes through the full gateway, approval rules included.
  def start_investigation(&)
    action_key = Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
    raise AbilityGateway::Denied.new(action_key) unless asker

    AbilityGateway.authorize!(
      principal: asker, action_key: action_key, workspace: workspace,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: conversation.incident_id }, &
    )
  end

  def asker_name = asker.try(:display_name) || "The person asking"

  private

  def self_approvable?(action)
    requirement = AbilityGateway.approval_requirement(workspace, action, action.key, {}, {})
    requirement.present? && Ability::Approval.self_approvable_by?(asker, requirement, workspace: workspace)
  end
end
