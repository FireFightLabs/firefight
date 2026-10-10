# The watches this chat keeps, going and ended. Fresh beats remembered, so each one still going reads what it follows
# again first, within its ceiling, and Halon answers how one is going from a reading taken now.
class Conversation::Tools::ListWatches < RubyLLM::Tool
  description "The watches this chat keeps, going and ended, with each step as it stands, when it was last read, and what " \
              "they said. Each one still going reads what it follows again first, so read it when the person asks how a " \
              "watch is going, and say so when it disagrees with what you or the watch said before."

  def self.tool_name = "list_watches"

  def initialize(turn)
    super()
    @turn = turn
  end

  def parameters_schema = { "type" => "object", "properties" => {}, "required" => [] }

  def call(tool_call: nil, **)
    watches = @turn.chat&.watches.to_a
    return "No watches in this chat." if watches.empty?

    watches.select(&:active?).each { |watch| Conversation::Watches.check!(watch) }
    shown = @turn.chat.watches.includes(:asker, :steps, :updates).to_a
    JSON.generate(shown.map { |watch| Chat::Watch::Shown.summary(watch) })
  end
end
