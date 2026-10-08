# Stops a watch this chat keeps, when the person asks to stop being told about it.
class Conversation::Tools::StopWatch < RubyLLM::Tool
  description "Stop a watch this chat keeps, when the person asks to stop following it. list_watches names them."

  def self.tool_name = "stop_watch"

  def initialize(turn)
    super()
    @turn = turn
  end

  def parameters_schema
    { "type" => "object", "properties" => { "watch" => { "type" => "string", "description" => "The watch's id, as start_watch or list_watches gave it" } },
      "required" => [ "watch" ] }
  end

  def call(tool_call: nil, **arguments)
    watch = @turn.chat&.watches&.find_by(id: arguments[:watch].to_s)
    return "No watch #{arguments[:watch]} in this chat. list_watches names them." unless watch

    blocked = Conversation::Watches.stop!(watch, by: @turn.asker)
    blocked || "Stopped watching #{watch.title}. Tell the person in a few words."
  end
end
