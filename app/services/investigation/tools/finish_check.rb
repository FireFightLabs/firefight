# Ends a scheduled check with what it looked at, what it found and what it could not read. Its words are the run's
# answer on the run's page, and the problems it noted are said by the delivery.
class Investigation::Tools::FinishCheck < RubyLLM::Tool
  def self.tool_name = FirefightAi::Monitor::FINISH_TOOL

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def name = self.class.tool_name

  def description
    "Finish the check. Nothing else ends a run. Note each problem with #{FirefightAi::Monitor::NOTE_TOOL} first."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "summary" => { "type" => "string", "description" => "What you looked at and what you found, in two or three sentences" },
        "gaps" => { "type" => "string", "description" => "What the check covers that you could not read, and why (optional)" }
      },
      "required" => [ "summary" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    return { error: "Say what you looked at and found in summary." } if asked["summary"].blank?

    @investigation.conclude!(summary: asked["summary"].to_s, gaps: asked["gaps"].presence)
    "Check recorded. The run is over."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    { error: error.message }
  end
end
