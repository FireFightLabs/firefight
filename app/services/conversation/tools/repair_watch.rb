# Gives a step of a watch this chat keeps a better read, so the same watch follows it from here rather than following
# nothing, and says what changed. Also how a step no read can show is let go.
class Conversation::Tools::RepairWatch < RubyLLM::Tool
  description "Repair a watch this chat keeps: give one of its steps a better read when its read found nothing to follow, " \
              "when a reading you took shows it follows the wrong thing, or when you are handed a step back. The same " \
              "watch follows it from here and says what changed. Try the new read once yourself first. Pass give_up " \
              "when no read can show it. list_watches names the watches and their steps."

  def self.tool_name = "repair_watch"

  def initialize(turn)
    super()
    @turn = turn
  end

  def parameters_schema
    step = Conversation::Tools::StartWatch::STEP
    {
      "type" => "object",
      "properties" => step["properties"].except("label").merge(
        "watch" => { "type" => "string", "description" => "The watch's id, as start_watch, list_watches or the hand back gave it" },
        "step" => { "type" => "string", "description" => "The step to repair, by its label" },
        "why" => { "type" => "string", "description" => "One short sentence on what was wrong with the old read, such as Run history only lists builds, not workflow runs" },
        "give_up" => { "type" => "boolean", "description" => "Stop following this step, when no read you can make shows it (optional)" }
      ),
      "required" => %w[watch step why]
    }
  end

  def call(tool_call: nil, **arguments)
    given = arguments.deep_transform_keys(&:to_s)
    watch = @turn.chat&.watches&.find_by(id: given["watch"].to_s)
    return "No watch #{given['watch']} in this chat. list_watches names them." unless watch

    step = watch.steps.find { |each| each.label.casecmp?(given["step"].to_s.strip) }
    return "#{Chat::Watch::Shown.name(watch)} has no step #{given['step']}. Its steps are: #{watch.steps.map(&:label).join(', ')}." unless step

    Conversation::Watches.repair!(watch, step, given.except("watch", "step", "why"), why: given["why"])
  end
end
