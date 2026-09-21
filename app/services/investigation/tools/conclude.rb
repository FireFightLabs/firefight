class Investigation::Tools::Conclude < RubyLLM::Tool
  # The class is namespaced, the model sees the plain name the prompt asks for.
  def self.tool_name = "conclude"

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def name = self.class.tool_name

  def description
    "Finish the investigation with the answer the evidence supports. Nothing else ends a run. " \
      "Every line of evidence is a claim and the step numbers it rests on, and one that cites no real step is refused."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "summary" => { "type" => "string", "description" => "What happened and why, in a few sentences, using only what the evidence shows" },
        "hypothesis" => { "type" => "string", "description" => "The assertion of the theory the evidence supports, exactly as recorded, or leave out when none holds" },
        "evidence" => {
          "type" => "array", "description" => "What the answer rests on, one item per claim",
          "items" => {
            "type" => "object",
            "properties" => {
              "claim" => { "type" => "string", "description" => "One thing the evidence shows, in a sentence" },
              "steps" => { "type" => "array", "items" => { "type" => "integer" }, "description" => "The step numbers of the tool results that show it" }
            },
            "required" => %w[claim steps]
          }
        },
        "gaps" => { "type" => "string", "description" => "What you could not check, and why it matters" }
      },
      "required" => [ "summary" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  def call(tool_call: nil, **arguments)
    asked = arguments.symbolize_keys
    @investigation.conclude!(
      summary: asked[:summary], hypothesis_assertion: asked[:hypothesis], evidence: Array(asked[:evidence]), gaps: asked[:gaps]
    )
    "Answer recorded. The run is over."
  rescue Investigation::Evidence::Refused => refused
    { error: refused.message }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    { error: error.message }
  end
end
