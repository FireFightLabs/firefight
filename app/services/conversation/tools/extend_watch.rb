# Gives a watch this chat keeps longer, when the person asks for more time, up to a day from when it started.
class Conversation::Tools::ExtendWatch < RubyLLM::Tool
  description "Give a watch this chat keeps more time, when the person asks for longer. minutes counts from when it " \
              "started, at most #{Chat::Watch::LONGEST.in_minutes.to_i}. list_watches names them."

  def self.tool_name = "extend_watch"

  def initialize(turn)
    super()
    @turn = turn
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "watch" => { "type" => "string", "description" => "The watch's id, as start_watch or list_watches gave it" },
        "minutes" => { "type" => "integer", "description" => "How long to watch in all, from when it started" }
      },
      "required" => %w[watch minutes]
    }
  end

  def call(tool_call: nil, **arguments)
    watch = @turn.chat&.watches&.find_by(id: arguments[:watch].to_s)
    return "No watch #{arguments[:watch]} in this chat. list_watches names them." unless watch
    return "Say how many minutes, more than it has now." unless arguments[:minutes].to_i.positive?
    return Chat::Watch::NOTHING_TO_STOP unless watch.extend_to!(arguments[:minutes])

    Conversation::LiveDelivery.watch_moved(watch.conversation)
    "#{watch.title} is now watched for up to #{Conversation::Watches::Shown.limit_label(watch)} from when it started. Tell the person in a few words."
  end
end
