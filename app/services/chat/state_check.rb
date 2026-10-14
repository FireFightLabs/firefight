# Halon reads how things stand now for a call that was approved some time after it was asked for, just before a person
# decides whether to run it. It reads as that person, only through tools that read, on a chat of its own owned by what
# is being checked, and reports once. When Halon is not available, or reads nothing it can report, the report says so,
# so the card is never left waiting.
class Chat::StateCheck
  # named is the call as a person reads it, such as "Rollback on service web on Faylee (Northflank)". asked is what it
  # was given, as label and value pairs.
  Call = Data.define(:named, :asked, :approved_by)

  COULD_NOT = "Halon could not read how this stands now.".freeze

  # ledger is more of what the activity log keeps on each read, such as the workflow run it was made for.
  def self.run(owner:, workspace:, principal:, source:, call:, ledger: {})
    new(owner: owner, workspace: workspace, principal: principal, source: source, ledger: ledger).run(call)
  end

  attr_reader :workspace

  def initialize(owner:, workspace:, principal:, source:, ledger: {})
    @owner = owner
    @workspace = workspace
    @principal = principal
    @source = source
    @ledger = ledger
  end

  def run(call)
    stopped = Investigation.unavailable_reason(@workspace) || (COULD_NOT unless @principal) || refusal_before_reading
    return unread(stopped) if stopped

    report = report_tool
    @chat = Chat.find_by(owner: @owner) || Chat.open!(owner: @owner, workspace: @workspace, model_choice: checker.ai_model)
    @chat.add_message(role: Chat::Message::ROLE_USER, content: question(call))
    presented = Chat::Tools.presented(self, checker.ai_model)
    checker.run(
      chat: @chat, tools: [ Chat::Tools::Open.new(self, offer: Chat::Tools.offer_to(@chat), presented: presented), Chat::Tools::ReadResult.new(self), report ] +
                         presented.loaded,
      deferred_tools: presented.deferred, max_spend_cents: max_spend_cents, answered: -> { report.report.present? }
    )
    report.report || unread(COULD_NOT)
  rescue StandardError => error
    Rails.logger.warn({ event: "state_check.failed", owner_type: @owner.class.name, owner_id: @owner.id, error: error.class.name }.to_json)
    unread(COULD_NOT)
  end

  # What the shared tools ask of whoever they run for. It reads as the person, never changes anything and keeps nothing.
  def acting_principal = @principal
  def chat = @chat
  def chat_owner = @owner
  def incident = nil
  def reads_only? = true
  def changes_memory? = false
  def uses_skills? = false
  def code_box_key = "state-check-#{@owner.id}"

  # A check only reads, so nobody listens for progress.
  def progress_listener(_tool_call_id) = nil
  def confirms?(*, **) = false
  def hold!(*, **) = false

  def refusal(action_key)
    "Not allowed: whoever this is checked for cannot use #{action_key}. Read what you can with the other tools."
  end

  # A check only reads, so nobody is offered a pack from it.
  def pack_refused!(_action_key, _tool_call_id) = nil

  def tool_call(action_key:, params: {}, scope: {}, approval_id: nil, holdable: true, **, &block)
    value = Chat::ToolCall.run!(
      workspace: @workspace, principal: @principal, action_key: action_key, params: params, scope: scope,
      context: @ledger.merge(source: @source, approval_id: approval_id).compact, holdable: holdable, &block
    )
    Chat::ToolCall::Outcome.new(value: value)
  end

  private

  def checker = @checker ||= FirefightAi::StateChecker.new(@workspace, inferable: @owner, member: (@principal if @principal.is_a?(WorkspaceMembership)))

  # What a check that read nothing reports, with why.
  def unread(reason) = Chat::CurrentState.unknown(reason)

  # Why it should not read at all, beyond Halon being unavailable, or nil.
  def refusal_before_reading = nil

  def max_spend_cents = @workspace.conversation_limits.max_spend_cents

  def report_tool = Report.new

  def question(call)
    given = call.asked.map { |label, value| "- #{label}: #{value}" }.join("\n")
    [ "#{call.approved_by} approved this call. Read how what it changes stands now.", "The call: #{call.named}", given.presence&.prepend("It was given:\n") ]
      .compact.join("\n\n")
  end

  # The one way the check ends.
  class Report < RubyLLM::Tool
    NAME = "report_state".freeze

    description "Say how what the call changes stands now, once you have read it. Call this once, last."
    parameter :now, description: "One or two plain sentences on how it stands now, naming what you read"
    parameter :change, description: "One of: #{Chat::CurrentState::CHANGES.join(', ')}"

    attr_reader :report

    def name = NAME

    def execute(now:, change:)
      @report = Chat::CurrentState::Report.new(state: now, change: change)
      "Reported."
    end
  end
end
