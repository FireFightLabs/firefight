# The watches this chat keeps, going and ended, so Halon answers how one is going from what it last read.
class Conversation::Tools::ListWatches < RubyLLM::Tool
  description "The watches this chat keeps, going and ended, with each step as it stands and what they said. Read it when " \
              "the person asks how a watch is going, instead of checking yourself."

  def self.tool_name = "list_watches"

  def initialize(turn)
    super()
    @turn = turn
  end

  def parameters_schema = { "type" => "object", "properties" => {}, "required" => [] }

  def call(tool_call: nil, **)
    watches = @turn.chat&.watches&.includes(:asker, :steps, :updates).to_a
    return "No watches in this chat." if watches.empty?

    JSON.generate(watches.map { |watch| Chat::Watch::Shown.summary(watch) })
  end
end
