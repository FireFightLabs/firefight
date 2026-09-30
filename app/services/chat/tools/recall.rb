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
        "about" => { "type" => "string", "description" => "A resource on the map or catalog entry, by name (optional)" },
        "words" => { "type" => "string", "description" => "Words the memory contains, such as database production (optional)" }
      }
    }
  end

  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    subject = Chat::Memory.subject_named(@agent_run.workspace, asked["about"])
    return "Nothing called #{asked['about']} is on the map or in the catalog." if asked["about"].present? && subject.nil?

    found = Chat::Memory.recall(@agent_run.workspace, subject: subject, query: asked["words"])
    return "Nothing is remembered about that yet." if found.empty?

    found.each(&:used!)
    found.map(&:line).join("\n")
  end
end
