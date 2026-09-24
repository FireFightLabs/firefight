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
        "gaps" => { "type" => "string", "description" => "What you could not check, and why it matters" },
        "suggest_incident" => {
          "type" => "boolean",
          "description" => "Only when there is no incident yet: true when what you found is hurting users now and the team should declare one"
        }
      },
      "required" => [ "summary" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  # The first answer is argued with before it is recorded, unless the budget has no room left for that.
  def call(tool_call: nil, **arguments)
    return FirefightAi::Investigator::CRITIQUE if !@investigation.budget_spent? && @investigation.ask_for_critique!

    asked = arguments.symbolize_keys
    evidence = Array(asked[:evidence])
    evidence.each_with_index { |item, index| @investigation.cited_steps!(item.to_h.stringify_keys["steps"], what: "Evidence #{index + 1}") }
    reread = Investigation::Rereading.new(@investigation).check(evidence)
    refuse_emptied_cause!(asked[:hypothesis], reread)

    @investigation.conclude!(
      summary: asked[:summary], hypothesis_assertion: asked[:hypothesis], evidence: reread.kept, gaps: asked[:gaps],
      suggest_incident: asked[:suggest_incident] == true
    )
    "Answer recorded. The run is over."
  rescue Investigation::Evidence::Refused => refused
    { error: refused.message }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    { error: error.message }
  end

  private

  # A cause with nothing left behind it is sent back with why, so the agent can cite what shows it or name no cause.
  def refuse_emptied_cause!(hypothesis, reread)
    return if hypothesis.blank? || reread.kept.any? || reread.dropped.empty?

    why = reread.dropped.map { |dropped| "\"#{dropped.claim}\": #{dropped.reason}" }.join(" ")
    raise Investigation::Evidence::Refused,
      "Every claim was dropped when read against the steps it cites. #{why} Conclude with claims those steps show, or with no cause."
  end
end
