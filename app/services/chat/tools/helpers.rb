# Hands independent checks to helpers that run at the same time, such as the logs, the recent deploys and the error
# rate of one service, and answers with what each reported. A helper only reads, as whoever the chat or run acts for.
class Chat::Tools::Helpers < RubyLLM::Tool
  NAME = "run_helpers".freeze
  CHECKS_ARG = "checks".freeze
  TITLE_ARG = "title".freeze
  BRIEF_ARG = "brief".freeze
  DEEP_ARG = "deep".freeze

  CHECK = {
    "type" => "object",
    "properties" => {
      TITLE_ARG => { "type" => "string", "description" => "A few words a person reads as the check's name, such as Logs of checkout" },
      BRIEF_ARG => { "type" => "string",
                     "description" => "What to read and what to look for, in a sentence or two, naming the resource, the connection " \
                                      "and the time window when you know them, such as Read checkout's error logs from 14:00 to 14:20 " \
                                      "UTC and say which errors are new and how often each appears" },
      DEEP_ARG => { "type" => "boolean",
                    "description" => "Run it on the main model, only for a check that reasons across several results, such as reading " \
                                     "code or comparing a failing run with one that passed (optional)" }
    },
    "required" => [ TITLE_ARG, BRIEF_ARG ]
  }.freeze

  description "Hand reads that do not depend on each other to helpers that run at the same time, each with its own narrow " \
              "brief, and get back a short report from each. Helpers only read, with the same reach as whoever you act for, " \
              "and spend from this question's budget. Use it when two to #{Chat::Helper::MAX_AT_ONCE} reads would otherwise " \
              "run one after another. At most #{Chat::Helper::MAX_PER_QUESTION} for one question."

  def self.tool_name = NAME

  # share is what the asking turn or run lends its helpers (Chat::Helpers::Share).
  def initialize(agent_run, share:)
    super()
    @agent_run = agent_run
    @share = share
  end

  def name = NAME

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        CHECKS_ARG => { "type" => "array", "items" => CHECK, "minItems" => 1, "maxItems" => Chat::Helper::MAX_AT_ONCE,
                        "description" => "The checks, each one read on its own" }
      },
      "required" => [ CHECKS_ARG ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    checks = self.class.checks_in(arguments)
    return failed(tool_call, "Give at least one check with a title and a brief.") if checks.empty?

    result = Chat::Helpers.run!(@agent_run, share: @share, tool_call_id: tool_call&.id.to_s, checks: checks)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id) if result.failed
    Chat::Tools.hand_over(@agent_run, NAME, Chat::ToolCall::Outcome.new(value: result.text))
  end

  # The checks as the model sent them, leaving out any without a brief.
  def self.checks_in(arguments)
    Array(arguments.stringify_keys[CHECKS_ARG]).filter_map do |given|
      given = given.to_h.stringify_keys
      brief = given[BRIEF_ARG].to_s.strip
      next if brief.empty?

      Chat::Helpers::Check.new(title: given[TITLE_ARG].to_s.strip.presence || brief.truncate(Chat::Helper::TITLE_LIMIT), brief: brief,
                               deep: ActiveModel::Type::Boolean.new.cast(given[DEEP_ARG]) == true)
    end
  end

  # What a person reads on the step, each check's title with its brief folded under it.
  def self.shown(arguments)
    checks = checks_in(arguments)
    Chat::Tools::Step.new(
      title: checks.size == 1 ? "One check by a helper" : "#{checks.size} checks at once", headline: checks.map(&:title).join(", "),
      asked: checks.map { |check| [ check.title, check.brief ] }, card: Chat::Tools::Card.new(kind: Chat::Tools::CARD_HELPERS, category: nil)
    )
  end

  private

  def failed(tool_call, text)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    text
  end
end
