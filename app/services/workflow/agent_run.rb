# What the tools a chat offers ask of whoever they run for, answered for one step of a workflow run. Every call goes
# through the gateway as whoever the run acts as, with the workflow as its source and the run named on the ledger row,
# so grants, configuration, approval rules and the activity log decide each one exactly as they do for Halon in a chat.
# Nobody is asked to confirm a call, since publishing the workflow was the decision, and a call an approval rule holds
# is kept here so the step can wait for it.
class Workflow::AgentRun
  attr_reader :workspace, :chat, :held, :failure_kind, :raw

  # reads_only is for a step that only reads, such as a skill, so a tool that can change things runs only as a read.
  # approval_id is an approval the step already holds for exactly this call.
  def initialize(run:, record: nil, chat: nil, reads_only: false, approval_id: nil)
    @run = run
    @record = record
    @workspace = run.workspace
    @chat = chat
    @reads_only = reads_only
    @approval_id = approval_id
    reset!
  end

  # Clears what the last call left, so each call is judged on its own.
  def reset!
    @held = nil
    @failure_kind = nil
    @raw = nil
  end

  def failed? = !@failure_kind.nil?

  def acting_principal = @run.acting_principal

  def chat_owner = @record || @run
  def incident = nil
  def reads_only? = @reads_only
  def changes_memory? = false
  def uses_skills? = false
  def code_box_key = "workflow-run-#{@run.id}"
  def posts_as_halon? = false

  # A run has nobody to show progress to as it happens, and nobody to ask.
  def progress_listener(_tool_call_id) = nil
  def confirms?(*, **) = false

  def hold!(approval, **)
    @held = approval
    true
  end

  def call_failed!(kind)
    @failure_kind = kind
  end

  def mark_step_failed!(*) = nil

  def refusal(action_key)
    "#{@run.workflow.name} may not use #{action_key}. An admin grants it on the workflow's page, under what it can do."
  end

  # A workflow's identity asks nobody for a pack. Its page says what it needs and an admin grants it there.
  def pack_refused!(_action_key, _tool_call_id) = nil

  def tool_call(action_key:, params: {}, scope: {}, approval_id: nil, holdable: true, **, &block)
    value = Chat::ToolCall.run!(
      workspace: @workspace, principal: acting_principal, action_key: action_key, params: params, scope: scope, holdable: holdable,
      context: { source: AbilityGateway::SOURCE_WORKFLOW, triggered_by_label: @run.ledger_label, approval_id: approval_id || @approval_id,
                 **Workflow::Run::Step.ledger_context(@run, @record) }.compact
    ) do |authorization|
      @raw = block.call(authorization)
    end
    Chat::ToolCall::Outcome.new(value: value)
  end
end
