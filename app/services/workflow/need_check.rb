# Before a change a run nobody pressed makes, Halon reads whether the problem the run answers is still there, as the
# workflow's own identity, only through reads, on the chat the step's row owns. Its model calls are the run's, so they
# count against the workflow's spending ceiling, and with nothing left of it Halon does not read at all. The step makes
# the change when it is still needed, is skipped when the problem cleared, and stops when nobody could tell.
class Workflow::NeedCheck < Chat::StateCheck
  STILL_NEEDED = "still_needed".freeze
  CLEARED = "cleared".freeze
  UNKNOWN = "unknown".freeze
  VERDICTS = [ STILL_NEEDED, CLEARED, UNKNOWN ].freeze
  OUT_OF_ROOM = "This run reached its spending ceiling, so Halon did not check.".freeze
  # How much of what started the run Halon is shown.
  STARTED_LIMIT = 4_000

  # named is the change as a person reads it, asked what it was given as label and value pairs.
  Call = Data.define(:named, :asked)

  # What Halon read and whether the change is still needed.
  Verdict = Data.define(:state, :verdict) do
    def initialize(state:, verdict:)
      super(state: state.to_s.strip.presence, verdict: VERDICTS.include?(verdict.to_s) ? verdict.to_s : UNKNOWN)
    end
  end

  def self.run(run:, owner:, call:)
    new(run: run, owner: owner).run(call)
  end

  def initialize(run:, owner:)
    @run = run
    super(owner: owner, workspace: run.workspace, principal: run.acting_principal, source: AbilityGateway::SOURCE_WORKFLOW,
          ledger: { triggered_by_label: run.ledger_label, **Workflow::Run::Step.ledger_context(run, owner.is_a?(Workflow::Run::Step) ? owner : nil) }.compact)
  end

  private

  def checker = @checker ||= FirefightAi::NeedChecker.new(@workspace, inferable: @owner)

  def unread(reason) = Verdict.new(state: reason, verdict: UNKNOWN)

  def refusal_before_reading = (OUT_OF_ROOM unless max_spend_cents.positive?)

  def max_spend_cents = @max_spend_cents ||= @run.room_cents(@workspace.conversation_limits.max_spend_cents)

  def report_tool = Report.new

  def question(call)
    given = call.asked.map { |label, value| "- #{label}: #{value}" }.join("\n")
    [
      "#{@run.workflow.name}, a workflow, is about to make this change on its own. Read whether the problem it answers is still there.",
      "What started the run: #{started}",
      "The change: #{call.named}",
      given.presence&.prepend("It was given:\n")
    ].compact.join("\n\n")
  end

  def started
    kind = Workflow::TriggerKinds.find(@run.trigger_kind)&.label || @run.trigger_kind.to_s.humanize
    payload = @run.trigger_payload.to_h
    payload.empty? ? kind : "#{kind}, with #{JSON.pretty_generate(payload).truncate(STARTED_LIMIT)}"
  end

  # The one way the check ends.
  class Report < RubyLLM::Tool
    NAME = "report_need".freeze

    description "Say whether the problem the change answers is still there, once you have read it. Call this once, last."
    parameter :now, description: "One or two plain sentences on how it stands now, naming what you read"
    parameter :verdict, description: "One of: #{VERDICTS.join(', ')}"

    attr_reader :report

    def name = NAME

    def execute(now:, verdict:)
      @report = Verdict.new(state: now, verdict: verdict)
      "Reported."
    end
  end
end
