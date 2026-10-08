# How the agent finds its tools. It reads a short map of groups, which travels in this tool's own
# description, and opens the one it needs. Our code never guesses which tool the model means.
class Chat::Tools::Open < RubyLLM::Tool
  # Past this a group's tools are listed first and the agent names the ones it wants loaded.
  LARGE_GROUP = 15

  STATE_WORDS = {
    Chat::Tools::STATE_READY => "ready",
    Chat::Tools::STATE_NOT_GRANTED => "not granted to whoever you are acting as",
    Chat::Tools::STATE_READS_ONLY => "not used while investigating, since an investigation only reads",
    Chat::Tools::STATE_NOT_CONNECTED => "nothing connected",
    Chat::Tools::STATE_SWITCHED_OFF => "connected, but no tools switched on"
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
      A group that is not granted, has nothing connected or has no tools switched on cannot be used, and that is worth saying in your answer.
    TEXT
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "group" => { "type" => "string", "enum" => views.map(&:key), "description" => "The group to open" },
        "tools" => {
          "type" => "array", "items" => { "type" => "string" },
          "description" => "Tools to load by name. A large group that listed its tools first loads only these, and a name that sits in another group is loaded from there (optional)"
        }
      },
      "required" => [ "group" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  def call(tool_call: nil, **arguments)
    asked = arguments.symbolize_keys
    open(asked[:group].to_s, Array(asked[:tools]).map(&:to_s))
  end

  private

  def views = @views ||= Chat::Tools::Groups.for(@agent_run)

  def open(key, wanted)
    current = Chat::Tools::Groups.for(@agent_run)
    view = current.find { |one| one.key == key }
    elsewhere = elsewhere(current, view, wanted)
    return [ "There is no group called #{key}. The groups are: #{views.map(&:key).join(', ')}.", elsewhere ].compact.join("\n\n") unless view
    return [ switched_off(view), elsewhere ].compact.join("\n\n") if view.state == Chat::Tools::STATE_SWITCHED_OFF
    return [ nothing_connected(view), elsewhere ].compact.join("\n\n") if view.entries.empty?
    chosen = chosen_from(view, wanted)
    return [ listed_first(view), elsewhere ].compact.join("\n\n") if chosen.empty?

    @offer.call(chosen.filter_map(&:tool))
    [ listing(chosen), elsewhere, idle(view), skills_for(chosen), as_read(chosen) ].compact.join("\n\n")
  end

  # Anything not ready describes the moment it was read, so a person who says they changed it is checked again.
  def as_read(entries) = (Chat::StaleRefusals::AS_READ if entries.any? { |entry| entry.tool.nil? })

  # Seen in a real chat, Halon opened Coding agents for the code host's own code change tool, read that nothing was
  # connected there and twice told the person no pull request could be opened. A tool is found by its name in whichever
  # group holds it, and loaded when whoever acts may use it.
  def elsewhere(current, view, wanted)
    names = wanted.uniq - (view ? view.entries.map(&:name) : [])
    return if names.empty?

    found = current.reject { |one| one.key == view&.key }.flat_map { |one| one.entries.map { |entry| [ entry, one ] } }.index_by { |entry, _| entry.name }
    ready = names.filter_map { |name| found[name]&.first }.select(&:tool)
    @offer.call(ready.map(&:tool)) if ready.any?
    said = names.map do |name|
      entry, holder = found[name]
      next "There is no tool called #{name} in any group." unless entry
      next "#{name} is in the group #{holder.title} (#{holder.key}), so it was loaded from there: #{entry.description} (ready to call)" if entry.tool

      "#{name} is in the group #{holder.title} (#{holder.key}). It exists, but #{STATE_WORDS.fetch(entry.state)}."
    end
    [ *said, (Chat::StaleRefusals::AS_READ if ready.size < names.size) ].compact.join("\n")
  end

  # A connection with every tool off has nothing to list, so it would go unseen beside the others in its group.
  def idle(view)
    return if view.idle.empty?

    view.idle.map do |name|
      "#{name} is connected, but none of its tools are switched on. An admin can switch them on in Integrations. " \
        "Say so when the person asks about what it reaches, rather than using another connection's tools for it."
    end.join("\n")
  end

  # A skill has the steps for these tools, so the agent is pointed at it here, where it is about to call them, rather
  # than trusting a line in the prompt it read long before.
  def skills_for(entries)
    sources = entries.map(&:source).uniq
    fitting = Chat::Skill.available_to(@agent_run.workspace).select { |skill| sources.include?(skill.source) && (skill.tools & entries.map(&:handle)).any? }
    return if fitting.empty?

    "Skills with the steps for these tools. Load the one that fits the question with use_skill first, which also loads the tools it needs:\n" \
      "#{fitting.map { |skill| "#{skill.name}: #{skill.used_when}" }.join("\n")}"
  end

  # Names only narrow a large group. A small one opens whole whatever was named, since a model
  # that guesses at names before reading any would otherwise lose a turn to being corrected.
  def chosen_from(view, wanted)
    return view.entries unless large?(view)

    view.entries.select { |entry| wanted.include?(entry.name) }
  end

  def large?(view) = view.entries.size > LARGE_GROUP

  # A skill loads the tools it names, so a large group points at its skills before asking for names.
  def listed_first(view)
    [
      "#{listing(view.entries)}\n" \
        "This group is large, so nothing was loaded. Call #{name} again with this group and tools, and name the ones you need.",
      idle(view), skills_for(view.entries)
    ].compact.join("\n\n")
  end

  # An empty group says nothing about the others, so it never ends the search for what the person asked.
  OTHER_GROUPS = "That is only this group. Before telling the person something cannot be done, check whether another group " \
                 "answers it, and open that one. Say it could not be checked only once no group does.".freeze

  def nothing_connected(view)
    "Nothing is connected for #{view.title} in this workspace. #{view.could_connect.to_sentence} can be connected by an admin. #{OTHER_GROUPS} #{Chat::StaleRefusals::AS_READ}"
  end

  def switched_off(view)
    one = view.connected.one?
    "#{view.connected.to_sentence} #{one ? 'is' : 'are'} connected, but none of #{one ? 'its' : 'their'} tools are switched on. " \
      "An admin can switch them on under Integrations. #{OTHER_GROUPS} #{Chat::StaleRefusals::AS_READ}"
  end

  def listing(entries)
    entries.map do |entry|
      ready = entry.state == Chat::Tools::STATE_READY
      "#{entry.name}: #{entry.description} (#{ready ? 'ready to call' : "exists, but #{STATE_WORDS.fetch(entry.state)}"})"
    end.join("\n")
  end
end
