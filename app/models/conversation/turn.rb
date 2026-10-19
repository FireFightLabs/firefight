# Tool calls act as the person who asked, so a chat reaches exactly what they can in the dashboard.
class Conversation::Turn
  attr_reader :conversation, :asker

  delegate :workspace, :incident, :chat, :code_box_key, to: :conversation

  # reads_only is for a turn nobody asked for in the moment, such as a watch handing back to Halon, which may read and
  # re-plan but never change anything. approved_plan is a scheduled plan whose time came, whose changes the person
  # approved ahead.
  def initialize(conversation, asker:, reads_only: false, approved_plan: nil)
    @conversation = conversation
    @asker = asker
    @reads_only = reads_only
    @approved_plan = approved_plan
    @approved_tools = approved_plan&.approved_tools.to_a
    # The reads of one step run together (FirefightAi::AgentLoop::ToolsTogether), so what a turn keeps is kept once.
    @keeping = Monitor.new
  end

  # The scheduled plan this turn carries out with its approved-ahead tools, or nil.
  attr_reader :approved_plan

  # Whether this turn hands reads of connected systems to specialists, which its runner decides before the turn starts.
  attr_writer :asks_specialists

  def asks_specialists? = @asks_specialists == true

  def acting_principal = asker

  # A turn reads one catalogue (Chat::Tools.catalog), and the tools and skills it is built from, by part. While the runner
  # gets the turn ready each part is built once by its block. Once the model works, each read first asks version, a block
  # answering what the parts were read from (Chat::Tools.catalog_version), and builds them again only when that changed,
  # so a grant or a connection changed during the turn is still seen. A turn is never reused, so neither is its catalogue.
  def hold_catalog! = @catalog_held = true

  def release_catalog! = @catalog_held = false

  def catalog_held? = @catalog_held == true

  def catalog(version, part)
    @keeping.synchronize do
      unless @catalog_held && @catalog
        current = version.call
        @catalog = {} unless @catalog && current == @catalog_version
        @catalog_version = current
      end
      @catalog.fetch(part) { @catalog[part] = yield }
    end
  end

  # What a turn reads once and keeps as it goes, such as the chat's calls a skill reminder reads (Chat::Tools::SkillReminder).
  def kept(name) = @keeping.synchronize { (@kept ||= {})[name] ||= yield }

  # A tool of a scheduled plan whose changes the person approved ahead, run without asking since nobody may be there.
  def approved_ahead?(tool_name) = @approved_tools.include?(tool_name.to_s)

  # A chat may change things, each one confirmed by the person who asked.
  def reads_only? = @reads_only

  def changes_memory? = true

  # A turn's chat with the model is its conversation's.
  def chat_owner = conversation

  # A turn nobody can be credited with does nothing.
  # unasked is why the call runs without the person's yes, kept on the call when it was settled (#unasked_for), which the
  # activity log records.
  # capability is the capability Firefight built the call for, which the gateway reads (AbilityGateway.person_must_approve?).
  def tool_call(action_key:, params: {}, scope: {}, approval_id: nil, holdable: true, unasked: nil, capability: nil, **, &block)
    raise AbilityGateway::Denied.new(action_key) unless asker

    value = Chat::ToolCall.run!(
      workspace: workspace, principal: asker, action_key: action_key, params: params, scope: scope,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: conversation.incident_id, approval_id: approval_id,
                 unasked_reason: unasked&.reason, allowance_id: unasked&.allowance_id, capability: capability }.compact,
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
  # nothing read from outside has reached it since (Chat::Tools::Provenance). A tool a scheduled plan named when the
  # person approved it stops asking too. Neither applies where an approval rule does, since that rule wants each call
  # signed off. A change to permissions, a credential, an approval or a webhook always waits, whatever was allowed.
  def confirms?(action, allowed: false, tool_name: nil, declared_destructive: false, asks_a_person: false, **)
    return false unless asker
    return true if asks_a_person
    return true if action && self_approvable?(action)
    return false if allowed || @approved_tools.include?(tool_name.to_s)

    declared_destructive || (action.present? && (action.risk_level == Ability::Action::RISK_DESTRUCTIVE || !action.reversible))
  end

  # Why a change runs without the person's yes, kept on its call, or nil.
  Unasked = Data.define(:reason, :allowance_id)

  # Why this change runs without asking the person, or nil when they are asked. A safe change runs while the workspace
  # lets it (Workspace#safe_changes_without_asking), and a risky one when an enabled entry of the list of what Halon may
  # do without asking covers it (Ability::Allowance). Neither applies to a change an approval rule covers, which its
  # approver answers, nor to a change to who may do what, which a person always answers, nor in an outside agent's chat
  # or one in a tracker's issue, which act for a machine. action is the tool's action the call runs as, scope where it
  # runs, safe whether this call is safe (Integrations::SafeChanges), capability the capability Halon called through and
  # integration_id the connection it routed to. An entry of the list covers a call only when its values came from the
  # person, so never once anything from outside has reached the chat (outside, Chat::Tools::Provenance), the same as
  # Allow for the rest of this chat. Such a call is asked on the card as usual, which says why (#listed_but_read!). A safe
  # change runs either way.
  def unasked_for(action, scope: {}, params: {}, safe: false, capability: nil, integration_id: nil, tool_call_id: nil, outside: -> { true })
    return nil unless decides_for_person? && action && !action.read? && !action.asks_a_person?
    return nil if approval_requirement_for(action, scope, params).present?
    return Unasked.new(reason: Ability::Invocation::UNASKED_SAFE, allowance_id: nil) if safe && workspace.safe_changes_without_asking?

    allowance = Ability::Allowance.covering(workspace, action: action, environment_id: scope.to_h["environment"], capability: capability,
                                                       integration_id: integration_id)
    return nil unless allowance
    return listed_but_read!(tool_call_id, allowance) if tool_call_id.blank? || outside.call

    Unasked.new(reason: Ability::Invocation::UNASKED_ALLOWANCE, allowance_id: allowance.id)
  end

  # Whether an approval rule holds this change for someone other than the asker. Their approval is the one yes it needs,
  # so the asker is not asked first and the call goes straight to the approvers (#hold!), never asked twice.
  def asks_approvers_instead?(action, scope: {}, params: {})
    return false unless asker && chat && !conversation.mcp? && action

    requirement = approval_requirement_for(action, scope, params)
    requirement.present? && !Ability::Approval.self_approvable_by?(asker, requirement, workspace: workspace)
  end

  # Kept on the call, so it runs, is ledgered and is said as made without asking however the turn goes on.
  def unasked!(tool_call_id, unasked)
    return false unless unasked && chat && tool_call_id.present?

    chat.tool_calls.where(tool_call_id: tool_call_id.to_s).update_all(unasked_reason: unasked.reason, allowance_id: unasked.allowance_id,
                                                                     updated_at: Time.current)
    true
  end

  # The entry that would have covered the call is kept on it, with no reason to run unasked, so its card says the list
  # covers it and why it still asks (Chat::Tools::Confirmation#caution). Returns nil, since the person is asked.
  def listed_but_read!(tool_call_id, allowance)
    chat.tool_calls.where(tool_call_id: tool_call_id.to_s).update_all(allowance_id: allowance.id, unasked_reason: nil, updated_at: Time.current) if tool_call_id.present?
    nil
  end

  # Why a call that is running was settled to run without asking, or nil.
  def unasked_of(tool_call_id)
    return nil unless chat && tool_call_id.present?

    reason, allowance_id = chat.tool_calls.where(tool_call_id: tool_call_id.to_s).pick(:unasked_reason, :allowance_id)
    reason && Unasked.new(reason: reason, allowance_id: allowance_id)
  end

  # A call an approval rule held for someone else's approval is kept with the chat, so it is asked for there and runs once
  # approved. An outside agent's chat has nobody to ask, so its calls are not kept. Returns the held call, or false.
  def hold!(approval, tool_name:, tool_call_id:, target: nil)
    return false if conversation.mcp? || chat.nil?

    Chat::HeldCall.hold!(chat: chat, approval: approval, tool_name: tool_name, tool_call_id: tool_call_id, target: target)
  end

  # A change to memory in a chat is the asker's, so it goes through the gateway and the ledger like any tool call. No
  # approval rule holds it, since a broad rule would stop Halon remembering what it was just told. Returns what the block
  # returns.
  def memory_change(crud_action, params:, tool_name:, &)
    tool_call(action_key: Ability::Action.system_key(Ability::Action::RESOURCE_MEMORY, crud_action), params: params,
              tool_name: tool_name, label: nil, holdable: false, &).value
  end

  # A search of the handbook's long pages, as the asker, so it is in the activity log like any read.
  def handbook_read(params:, tool_name:, &)
    tool_call(action_key: Ability::Action::HANDBOOK_READ, params: params, tool_name: tool_name, label: nil, holdable: false, &).value
  end

  # Where what the agent remembers came from, and who taught it.
  def memory_source = conversation

  # Nobody in Firefight taught what a chat in an issue learned, since it acts as an agent, as a run does.
  def memory_teacher = (asker unless conversation.issue?)

  # A tool that changes something names the pack to ask for and the admins who can give it, so the person knows exactly
  # what to request and from whom.
  def refusal(action_key)
    return agent_refusal(action_key) if conversation.issue?

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

  def asker_name = asker.try(:actor_display_name) || "The person asking"

  private

  # A chat in an issue acts as Firefight's own agent, which holds only what an admin granted it, so nobody is offered a
  # pack.
  def agent_refusal(action_key)
    name = asker.try(:actor_display_name)
    "Not allowed: #{name}, the agent this chat acts as, has no grant for #{action_key} in this workspace. Say so, and that a " \
      "workspace admin can grant it to #{name} under Gateway, Permissions. #{Chat::StaleRefusals::AS_READ}"
  end

  # A person's own chat with Halon, where the person is there to answer.
  def decides_for_person? = asker.present? && chat.present? && !@reads_only && !conversation.mcp? && !conversation.issue?

  def approval_requirement_for(action, scope, params)
    AbilityGateway.approval_requirement(workspace, action, action.key, scope.to_h, { source: AbilityGateway::SOURCE_CONVERSATION }, params: params,
                                                                                                                                principal: asker)
  end

  def self_approvable?(action)
    requirement = AbilityGateway.approval_requirement(workspace, action, action.key, {}, {})
    requirement.present? && Ability::Approval.self_approvable_by?(asker, requirement, workspace: workspace)
  end
end
