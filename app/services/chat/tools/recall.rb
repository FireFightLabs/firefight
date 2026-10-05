# Reads what the workspace remembers about something, beyond the memories the chat or run started with.
class Chat::Tools::Recall < RubyLLM::Tool
  def self.tool_name = "recall"

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = self.class.tool_name

  def description
    "Read what this workspace remembers about a resource, a catalog entry, or a topic. Each memory says whether a " \
      "person confirmed it. Treat it as a hunch to check against live results, never proof."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "about" => { "type" => "string", "description" => "A resource on the map or catalog entry, by name or id, including one no longer on the map (optional)" },
        "words" => { "type" => "string", "description" => "Words the memory contains, such as database production (optional)" }
      }
    }
  end

  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    named = Chat::Memory.subject_named(@agent_run.workspace, asked["about"], removed: true)
    return named.refusal if named.refusal

    subject = named.subject
    found = Chat::Memory.recall(@agent_run.workspace, subject: subject, query: asked["words"])
    gone = "#{subject.name} is no longer on the map. It was last seen #{subject.removed_at.to_date.iso8601}, so check before relying on any of this." if subject.is_a?(ResourceMap::Resource) && subject.removed_at
    return [ gone, "Nothing is remembered about that yet." ].compact.join("\n") if found.memories.empty?

    found.memories.each(&:used!) if @agent_run.changes_memory?
    more = "#{found.more} more matched. Ask with more words, or name what it is about, to see them." if found.more.positive?
    [ gone, *found.memories.map(&:line), more ].compact.join("\n")
  end
end
