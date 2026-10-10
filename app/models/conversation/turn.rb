# Tool calls act as the person who asked, so a chat reaches exactly what they can in the dashboard.
class Conversation::Turn
  attr_reader :conversation, :asker

  delegate :workspace, :incident, :chat, :code_box_key, to: :conversation

  # reads_only is for a turn nobody asked for in the moment, such as a watch handing back to Halon, which may read and
  # re-plan but never change anything.
  def initialize(conversation, asker:, reads_only: false)
    @conversation = conversation
    @asker = asker
    @reads_only = reads_only
  end

  def acting_principal = asker

  # A chat may change things, each one confirmed by the person who asked.
  def reads_only? = @reads_only

  def changes_memory? = true

  # A turn's chat with the model is its conversation's.
  def chat_owner = conversation

  # A turn nobody can be credited with does nothing.
  def tool_call(action_key:, params: {}, scope: {}, approval_id: nil, holdable: true, **, &block)
    raise AbilityGateway::Denied.new(action_key) unless asker

    value = Chat::ToolCall.run!(
      workspace: workspace, principal: asker, action_key: action_key, params: params, scope: scope,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: conversation.incident_id, approval_id: approval_id }.compact,
      holdable: holdable, &block
    )
    Chat::ToolCall::Outcome.new(value: value)
  end

  # Hears how a long running call is going, such as a coding agent writing a change, so the turn can show it. Set by
  # whoever delivers the turn.
  def listen_to_progress(&block)
    @progress_listener = block
  end

  # What a tool call reports its progress to, or nil when nobody listens.
  def progress_listener(tool_call_id)
    listener = @progress_listener
    listener && ->(update) { listener.call(tool_call_id, update) }
  end

  # A code change asked for in this chat, written for the asker with their own words and what was read before the call.
  def code_agent_request(tool_call_id, evidence: [])
    CodeAgent::Request.new(
      principal: asker, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation, tool_call_id: tool_call_id, box_key: code_box_key,
      words: chat ? chat.readable_messages.where(role: Chat::Message::ROLE_USER).map(&:content) : [], evidence: evidence
    )
  end

  # A chat keeps no steps of its own, its tool calls carry how they went.
  def mark_step_failed!(_position, _kind) = nil

  # Only destructive or irreversible changes wait, plus those an approval rule lets the asker approve themselves, and a
  # tool that declares itself destructive. allowed is whether the person allowed the tool for the rest of the chat and
  # nothing read from outside has reached it since (Chat::Tools::Provenance), which stops it asking, except where an
  # approval rule applies, since that rule wants each call signed off.
  def confirms?(action, allowed: false, declared_destructive: false, **)
    return false unless asker
    return true if action && self_approvable?(action)
    return false if allowed

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

  # A tool that changes something names the pack to ask for and the admins who can give it, so the person knows exactly
  # what to request and from whom.
  def refusal(action_key)
    pack = Ability::Role.to_ask_for(Ability::Action.lookup(action_key, workspace))
    unless pack
      return "Not allowed: #{asker_name} cannot use #{action_key} in this workspace. Tell them, and that a workspace admin can grant it. " \
             "#{Chat::StaleRefusals::AS_READ}"
    end

    [ "Not allowed: #{asker_name} cannot use #{action_key} in this workspace. Tell them they do not have permission for it and that it " \
      "needs the #{pack.name} pack.", Ability::PackRequest.admins_sentence(workspace), "A card in the chat lets them ask the admins for it.",
      Chat::StaleRefusals::AS_READ ].compact.join(" ")
  end

  # A change refused for want of a pack leaves a card in the chat with Ask an admin, and a message in its platform
  # thread when it has one. Once per chat and pack. Nobody is asked until the person presses it.
  def pack_refused!(action_key, tool_call_id)
    request = asker && Ability::PackRequest.for_refusal(asker, Ability::Action.lookup(action_key, workspace))
    return unless request && chat

    refusal, made = Chat::PackRefusal.record!(chat: chat, pack_request: request, tool_call_id: tool_call_id)
    PackRefusalJob.perform_later(refusal.id) if made
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
