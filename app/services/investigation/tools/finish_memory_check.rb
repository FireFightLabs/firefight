# Ends the nightly memory check. Its answer is written by Firefight from what was settled, never by the model, so no
# memory's words are kept outside the memories themselves.
class Investigation::Tools::FinishMemoryCheck < RubyLLM::Tool
  def self.tool_name = FirefightAi::MemoryChecker::FINISH_TOOL

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def name = self.class.tool_name

  def description
    "Finish tonight's memory check. Nothing else ends the run. Settle every memory with #{FirefightAi::MemoryChecker::SETTLE_TOOL} first, " \
      "since one you leave is kept as not checked."
  end

  def parameters_schema = { "type" => "object", "properties" => {} }

  def call(tool_call: nil, **_arguments)
    review = @investigation.memory_review
    @investigation.conclude!(summary: review.summary)
    "Memory check recorded. The run is over."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    { error: error.message }
  end
end
