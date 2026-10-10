# open_tools in a replay, offered and answered the way a chat's is live. A chat starts holding only its own tools, and
# open_tools lists every group with what it covers and makes a group's tools callable. The groups are the scenario's
# own, named by whose the tools are, so nothing says a tool is missing or not granted when the scenario offers it.
class Conversation::Rehearsal::OpenTools < RubyLLM::Tool
  INTRO = "Make a group of tools callable. You hold almost no tools until you open the group that fits what you need next. The groups:".freeze
  READY = "ready to call".freeze
  # What a group covers, by whose its tools are. A provider's group is named for the provider.
  COVERS = {
    Chat::Skill::SOURCE_FIREFIGHT => "Firefight's own: incidents, runbooks, the resource map, the catalog, alerts and settings",
    "connected" => "Resources on the map, through whichever connection holds them: status, logs, metrics, deploys, run history and rollbacks"
  }.freeze

  # groups maps each group's key to the tool definitions in it. open takes the names to make callable and returns the
  # definitions it opened.
  def initialize(groups:, open:)
    super()
    @groups = groups
    @open = open
  end

  def name = Chat::Tools::Open.tool_name

  def description
    lines = @groups.map { |key, tools| "#{key}: #{COVERS.fetch(key) { "#{key.to_s.humanize}'s own tools" }}, such as #{tools.first(4).map(&:name).join(', ')} (ready)" }
    "#{INTRO}\n#{lines.join("\n")}"
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "group" => { "type" => "string", "enum" => @groups.keys, "description" => "The group to open" },
        "tools" => { "type" => "array", "items" => { "type" => "string" },
                     "description" => "Tools to load by name. A name that sits in another group is loaded from there (optional)" }
      },
      "required" => [ "group" ]
    }
  end

  def call(tool_call: nil, **arguments)
    given = arguments.stringify_keys
    group = @groups[given["group"].to_s]
    return "There is no group called #{given['group']}. The groups are: #{@groups.keys.join(', ')}." unless group

    named = Array(given["tools"]).map(&:to_s)
    wanted = named.any? ? @groups.values.flatten.select { |tool| named.include?(tool.name) } : group
    missing = named - wanted.map(&:name)
    opened = @open.call(wanted.map(&:name))
    [ opened.map { |tool| "#{tool.name}: #{tool.description.to_s.squish} (#{READY})" }.join("\n"),
      *missing.map { |tool_name| "There is no tool called #{tool_name} in any group." } ].compact_blank.join("\n\n")
  end
end
