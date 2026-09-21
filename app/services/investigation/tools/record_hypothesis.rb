class Investigation::Tools::RecordHypothesis < RubyLLM::Tool
  # The class is namespaced, the model sees the plain name the prompt asks for.
  def self.tool_name = "record_hypothesis"

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def name = self.class.tool_name

  def description
    "Record a theory about the cause, or update one you recorded earlier. " \
      "Marking one supported or refuted needs the step numbers that showed it."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "assertion" => { "type" => "string", "description" => "The theory in one sentence, such as 'The 14:02 deploy raised the connection pool size'" },
        "status" => { "type" => "string", "enum" => Investigation::Hypothesis::STATUSES, "description" => "open, supported or refuted" },
        "confidence" => { "type" => "number", "description" => "Between 0 and 1, how sure the evidence makes you" },
        "steps" => { "type" => "array", "items" => { "type" => "integer" }, "description" => "The step numbers of the tool results that support or refute it" }
      },
      "required" => [ "assertion" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  def call(tool_call: nil, **arguments)
    asked = arguments.symbolize_keys
    hypothesis = @investigation.record_hypothesis!(
      assertion: asked[:assertion], status: asked[:status], confidence: asked[:confidence], steps: Array(asked[:steps])
    )
    "Recorded theory #{hypothesis.position} as #{hypothesis.status}."
  rescue Investigation::Evidence::Refused => refused
    { error: refused.message }
  rescue ActiveRecord::RecordInvalid => error
    { error: error.record.errors.full_messages.to_sentence }
  end
end
