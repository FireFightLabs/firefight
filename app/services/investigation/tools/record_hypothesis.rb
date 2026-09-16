class Investigation::Tools::RecordHypothesis < RubyLLM::Tool
  description "Record a theory about the cause, or update one you recorded earlier."
  parameter :assertion, description: "The theory in one sentence, such as 'The 14:02 deploy raised the connection pool size'"
  parameter :status, description: "open, supported or refuted", required: false
  parameter :confidence, type: :number, description: "Between 0 and 1, how sure the evidence makes you", required: false

  # The class is namespaced, the model sees the plain name the prompt asks for.
  def self.tool_name = "record_hypothesis"

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def execute(assertion:, status: nil, confidence: nil)
    hypothesis = @investigation.record_hypothesis!(assertion: assertion, status: status, confidence: confidence)
    "Recorded theory #{hypothesis.position} as #{hypothesis.status}."
  rescue ActiveRecord::RecordInvalid => error
    { error: error.record.errors.full_messages.to_sentence }
  end
end
