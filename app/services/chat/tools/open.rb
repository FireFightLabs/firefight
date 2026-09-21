# How the agent finds its tools. It reads a short map of groups, which travels in this tool's own
# description, and opens the one it needs. Our code never guesses which tool the model means.
class Chat::Tools::Open < RubyLLM::Tool
  # Past this a group's tools are listed first and the agent names the ones it wants loaded.
  LARGE_GROUP = 15

  STATE_WORDS = {
    Chat::Tools::STATE_READY => "ready",
    Chat::Tools::STATE_NOT_GRANTED => "not granted to whoever you are acting as",
    Chat::Tools::STATE_NOT_CONNECTED => "nothing connected"
  }.freeze

  def self.tool_name = "open_tools"

  def initialize(agent_run, offer:)
    super()
    @agent_run = agent_run
    @offer = offer
  end

  def name = self.class.tool_name

  # Built once, so the front of every request in a run stays the same.
  def description
    @description ||= <<~TEXT.strip
      Make a group of tools callable. You hold almost no tools until you open the group that fits what you need next. The groups:
      #{views.map { |view| "#{view.title}: #{view.covers} (#{STATE_WORDS.fetch(view.state)})" }.join("\n")}
      A group that is not granted or has nothing connected cannot be used, and that is worth saying in your answer.
    TEXT
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "group" => { "type" => "string", "enum" => views.map(&:key), "description" => "The group to open" },
        "tools" => {
          "type" => "array", "items" => { "type" => "string" },
          "description" => "Only for a large group that listed its tools first: the names to load"
        }
      },
      "required" => [ "group" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    open(arguments[:group].to_s, Array(arguments[:tools]).map(&:to_s))
  end

  private

  def views = @views ||= Chat::Tools::Groups.for(@agent_run)

  def open(key, wanted)
    view = Chat::Tools::Groups.for(@agent_run).find { |one| one.key == key }
    return "There is no group called #{key}. The groups are: #{views.map(&:key).join(', ')}." unless view
    return nothing_connected(view) if view.entries.empty?
    return listed_first(view) if large?(view) && wanted.empty?

    chosen = wanted.empty? ? view.entries : view.entries.select { |entry| wanted.include?(entry.name) }
    return "None of those are in #{view.title}. It holds: #{view.entries.map(&:name).join(', ')}." if chosen.empty?

    @offer.call(chosen.filter_map(&:tool))
    listing(chosen)
  end

  def large?(view) = view.entries.size > LARGE_GROUP

  def listed_first(view)
    "#{listing(view.entries)}\n" \
      "This group is large, so nothing was loaded. Call #{name} again with this group and tools, and name the ones you need."
  end

  def nothing_connected(view)
    "Nothing is connected for #{view.title} in this workspace. #{view.could_connect.to_sentence} can be connected by an admin. Say this is what you could not check rather than guessing."
  end

  def listing(entries)
    entries.map do |entry|
      ready = entry.state == Chat::Tools::STATE_READY
      "#{entry.name}: #{entry.description} (#{ready ? 'ready to call' : 'exists, but not granted to whoever you are acting as'})"
    end.join("\n")
  end
end
