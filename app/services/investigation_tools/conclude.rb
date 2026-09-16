class InvestigationTools::Conclude < RubyLLM::Tool
  description "Finish the investigation with the answer the evidence supports. Nothing else ends a run."
  parameter :summary, description: "What happened and why, in a few sentences, using only what the evidence shows"
  parameter :hypothesis, description: "The assertion of the theory the evidence supports, exactly as recorded, or leave empty when none holds", required: false
  parameter :evidence, type: :array, description: "What the answer rests on, one item per line of evidence", required: false
  parameter :gaps, description: "What you could not check, and why it matters", required: false

  # The class is namespaced, the model sees the plain name the prompt asks for.
  def self.tool_name = "conclude"

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def execute(summary:, hypothesis: nil, evidence: nil, gaps: nil)
    @investigation.conclude!(
      summary: summary, hypothesis_assertion: hypothesis, evidence: Array(evidence), gaps: gaps
    )
    "Answer recorded. The run is over."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    { error: error.message }
  end
end
