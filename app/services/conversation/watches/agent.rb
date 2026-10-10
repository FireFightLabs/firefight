# What a watch reads with when a step names one of Halon's tools rather than a capability: every tool the person who
# asked may read with, by the name Halon calls it, through the gateway as them. It only reads, so a tool that changes
# something is never handed over, and one that can do both, such as a provider's API request, only reads through its
# guard. Nothing waits for a confirmation, and a read an approval rule covers is never made.
class Conversation::Watches::Agent
  # meter counts each call, the same one the watch's Reader counts on.
  def initialize(workspace:, asker:, conversation:, meter: Chat::Watch::Meter.new(nil))
    @workspace = workspace
    @asker = asker
    @conversation = conversation
    @meter = meter
  end

  # Ready for the asker and reading only, by the name Halon calls each.
  def tools
    @tools ||= Chat::Tools.catalog(self).select { |entry| entry.state == Chat::Tools::STATE_READY && entry.tool }.index_by(&:name)
  end

  # Whether the last call was refused or the provider failed it.
  def failed? = @failed.present?

  def call_failed!(kind)
    @failed = kind
  end

  def started_call! = @failed = nil

  # What the shared tools ask of whoever they run for.
  def acting_principal = @asker
  attr_reader :workspace
  def chat = nil
  def chat_owner = @conversation
  def incident = @conversation.try(:incident)
  def reads_only? = true
  def changes_memory? = false
  def uses_skills? = false
  def code_box_key = @conversation.code_box_key
  def progress_listener(_tool_call_id) = nil
  def confirms?(*, **) = false
  def hold!(*, **) = false
  def mark_step_failed!(_position, _kind) = nil
  def pack_refused!(_action_key, _tool_call_id) = nil

  def refusal(action_key) = "#{@asker.try(:display_name) || 'The person who asked'} may not use #{action_key}."

  # A tool no approval rule holds, such as the map search, is read whatever the rules say.
  def tool_call(action_key:, params: {}, scope: {}, approval_id: nil, holdable: true, **, &block)
    raise Conversation::Watches::Reader::Refused, "An approval rule covers #{action_key}, and nobody is there to approve each read." if
      holdable && Chat::ToolCall.held_by_rule?(workspace: workspace, action_key: action_key, scope: scope, params: params)

    @meter.spend!
    value = Chat::ToolCall.run!(
      workspace: workspace, principal: acting_principal, action_key: action_key, params: params, scope: scope,
      context: { source: Chat::Watch::SOURCE, incident_id: @conversation.try(:incident_id), approval_id: approval_id }.compact,
      holdable: holdable, &block
    )
    Chat::ToolCall::Outcome.new(value: value)
  end
end
