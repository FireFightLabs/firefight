# How a check settles the finding it checked: keep it, as reported or corrected, or drop it with why, and what it showed
# of each earlier finding it touched. Nothing is written here. The check reads what was said once it ends.
class PullRequestReview::SettleFinding < RubyLLM::Tool
  NAME = "settle_finding".freeze
  KEEP = "keep".freeze
  DROP = "drop".freeze
  VERDICTS = [ KEEP, DROP ].freeze
  CONFIRM = "confirm".freeze
  STRENGTHEN = "strengthen".freeze
  WITHDRAW = "withdraw".freeze
  OUTCOMES = [ CONFIRM, STRENGTHEN, WITHDRAW ].freeze

  Earlier = Data.define(:number, :outcome, :note, :changes)
  Settled = Data.define(:verdict, :reason, :corrections, :earlier) do
    def keep? = verdict == KEEP
  end

  # numbers are the earlier findings the check may name.
  def initialize(numbers)
    super()
    @numbers = numbers
  end

  attr_reader :settled

  def name = NAME

  def description
    "Settle the finding you checked, once, last: keep it, as reported or with your corrections, or drop it with why. Say what " \
      "your check showed of each earlier finding it touched."
  end

  def parameters_schema
    labels = {
      "category" => { "type" => "string", "enum" => PullRequestReview::Finding::CATEGORIES },
      "severity" => { "type" => "string", "enum" => PullRequestReview::Finding::SEVERITIES },
      "effort" => { "type" => "string", "enum" => PullRequestReview::Finding::EFFORTS },
      "serious" => { "type" => "boolean" }
    }
    {
      "type" => "object",
      "properties" => {
        "verdict" => { "type" => "string", "enum" => VERDICTS },
        "reason" => { "type" => "string", "description" => "What your reads showed, in one or two plain sentences, naming the lines or results" },
        "corrections" => {
          "type" => "object", "description" => "Only what you would change about the finding you keep (optional)",
          "properties" => labels.merge(
            "line" => { "type" => "integer" }, "claim" => { "type" => "string" }, "why" => { "type" => "string" },
            "failure_chain" => { "type" => "array", "items" => { "type" => "string" } }
          )
        },
        "earlier" => {
          "type" => "array", "description" => "Each earlier finding your check touched (optional)",
          "items" => {
            "type" => "object",
            "properties" => {
              "finding" => { "type" => "integer", "description" => "Its number" },
              "outcome" => { "type" => "string", "enum" => OUTCOMES },
              "note" => { "type" => "string", "description" => "What your check showed of it, in one plain sentence" },
              "changes" => {
                "type" => "object", "description" => "For strengthen, what to change about it (optional)",
                "properties" => labels.merge("why" => { "type" => "string" })
              }
            },
            "required" => %w[finding outcome note]
          }
        }
      },
      "required" => %w[verdict reason]
    }
  end

  def settled? = !@settled.nil?

  # The arguments match the schema above, not an execute signature, so skip the base check. A settlement naming an
  # earlier finding that is not listed, or one that withdraws without a note, is refused with why.
  def call(tool_call: nil, **arguments)
    given = arguments.deep_stringify_keys
    verdict = given["verdict"].to_s
    reason = given["reason"].to_s.squish
    return "Not settled. verdict is #{VERDICTS.join(' or ')}, and reason says what your reads showed." unless VERDICTS.include?(verdict) && reason.present?

    earlier = Array(given["earlier"]).select { |each| each.is_a?(Hash) }.map do |each|
      Earlier.new(number: each["finding"].to_i, outcome: each["outcome"].to_s, note: each["note"].to_s.squish, changes: each["changes"].is_a?(Hash) ? each["changes"] : {})
    end
    problems = earlier.reject { |each| @numbers.include?(each.number) }.map { |each| "There is no earlier finding #{each.number}." } +
               earlier.reject { |each| OUTCOMES.include?(each.outcome) && each.note.present? }.map { |each| "Finding #{each.number} needs an outcome and a note." }
    return "Not settled. #{problems.uniq.join(' ')}" if problems.any?

    @settled = Settled.new(verdict: verdict, reason: reason, corrections: given["corrections"].is_a?(Hash) ? given["corrections"] : {}, earlier: earlier)
    "Settled."
  end
end
