# One slow problem a scheduled check found, with the steps that show it. It is kept as an Investigation::Notice, which
# decides whether it is news (new, worse, or back after a long time) and so whether the run's end says it.
class Investigation::Tools::NoteProblem < RubyLLM::Tool
  def self.tool_name = FirefightAi::Monitor::NOTE_TOOL

  # Raised by a security event, never by a check.
  # A resource or a date the agent named that cannot be read, said back so it can fix it.
  class Unknown < StandardError; end

  SIGNALS = (Investigation::Notice::SIGNALS - [ Investigation::Notice::SIGNAL_LEAKED_SECRET ]).freeze

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def name = self.class.tool_name

  def description
    "Record one problem this check found that needs a person, with the steps that show it. Firefight says it in the team's " \
      "channel when it is new or worse than last time, and stays quiet otherwise."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "signal" => { "type" => "string", "enum" => SIGNALS, "description" => "What kind of problem it is" },
        "topic" => { "type" => "string", "description" => "What it is about in a few words, the same each time for the same problem, " \
                                                          "such as the data volume of orders-db or the AWS bill" },
        "resource" => { "type" => "string", "description" => "The resource on the map it is about, by its id or name, when it is about one (optional)" },
        "summary" => { "type" => "string", "description" => "What is happening and by when, in one or two plain sentences a team reads in " \
                                                            "a channel, such as: The orders-db volume is 81% full and grows about 1.2% a day, so it is full around Oct 28." },
        "severity" => { "type" => "string", "enum" => Investigation::Notice::SEVERITIES,
                        "description" => "low is worth knowing, medium needs doing within weeks, high needs doing now" },
        "due_on" => { "type" => "string", "description" => "The day it becomes a problem, as YYYY-MM-DD, when there is one (optional)" },
        "steps" => { "type" => "array", "items" => { "type" => "integer" }, "description" => "The step numbers of the results that show it" }
      },
      "required" => %w[signal topic summary severity steps]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    @investigation.cited_steps!(asked["steps"], what: "This problem")
    reading = Investigation::Notice::Reading.new(
      signal: asked["signal"].to_s.presence_in(SIGNALS) || Investigation::Notice::SIGNAL_OTHER, topic: asked["topic"].to_s,
      summary: asked["summary"].to_s, severity: asked["severity"].to_s.presence_in(Investigation::Notice::SEVERITIES) || Investigation::Notice::SEVERITY_LOW,
      due_on: due_on(asked["due_on"]), resource: resource(asked["resource"])
    )
    return { error: "Say what the problem is about in topic and what is happening in summary." } if reading.topic.blank? || reading.summary.blank?

    Investigation::Notice.observe!(@investigation.workspace, reading, check: @investigation.check, investigation: @investigation)
    "Noted. Note any other problem the same way, then call #{FirefightAi::Monitor::FINISH_TOOL}."
  rescue Investigation::Evidence::Refused, Unknown => refused
    { error: refused.message }
  end

  private

  def due_on(value)
    return nil if value.blank?

    Date.iso8601(value.to_s)
  rescue Date::Error
    raise Unknown, "due_on #{value} is not a date. Give it as YYYY-MM-DD."
  end

  def resource(reference)
    return nil if reference.blank?

    found = ResourceMap::Resource.visible_to(@investigation.acting_principal, @investigation.workspace)
                                 .referenced(@investigation.workspace, reference).present.to_a
    raise Unknown, ResourceMap::Resource.not_found_words(reference) if found.empty?
    raise Unknown, "More than one resource is called #{reference}. Name it by its id on the map." if found.size > 1

    found.first
  end
end
