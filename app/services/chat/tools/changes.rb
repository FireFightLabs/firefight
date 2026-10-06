# A connection added, removed, renamed, pointed somewhere else or with tools switched on or off while a chat or run goes
# on. The agent remembers the tools it found (Chat#found_tool_names) and would carry on with that list, telling a
# person a tool is missing that an admin has just switched on. Each turn, and between a tool's result and the next model
# call, the connections are compared with what the chat last saw. The agent is told what changed in a short note, tools
# that are gone are forgotten, and a connection's newly switched on tools are offered at once when the agent had opened
# their group before.
module Chat::Tools::Changes
  # note is what the agent is told, nil when nothing changed, and offered the tools to add to the live chat.
  Caught = Data.define(:note, :offered)
  NOTHING = Caught.new(note: nil, offered: [])

  # How each connection stood, by id, with the name a person tells it by, what it reaches, whether it is on, and the tools it
  # has switched on, as the agent calls them.
  def self.snapshot(workspace)
    workspace.integrations.where(deleted_at: nil).includes(:tools, :integration_environments).order(:created_at).to_h do |integration|
      tools = integration.tools.select { |tool| tool.enabled? && tool.available? }.map(&:model_facing_name).sort
      [ integration.id.to_s, { "name" => integration.display_name, "reach" => integration.reach, "on" => integration.operational?,
                               "group" => Chat::Tools::Groups.of_connection(integration), "tools" => tools } ]
    end
  end

  # Compares the connections with what the chat saw last and records them. A chat that never looked is only recorded.
  def self.catch_up!(agent_run, chat)
    now = snapshot(agent_run.workspace)
    seen = chat.connections_seen
    return NOTHING if seen == now

    chat.update_column(:connections_seen, now)
    return NOTHING if seen.nil?

    lines = changes(seen, now)
    return NOTHING if lines.empty?

    offered = refresh_found_tools!(agent_run, chat, seen, now)
    groups = (now.keys | seen.keys).reject { |id| seen[id] == now[id] }.map { |id| (now[id] || seen[id])["group"] }.uniq
    Caught.new(note: note(lines, groups), offered: offered)
  end

  def self.note(lines, groups)
    <<~TEXT.strip
      The connections changed since you last looked:
      #{lines.map { |line| "- #{line}" }.join("\n")}
      Tools that are gone are no longer yours to call. Before you answer anything about these connections, open #{groups.to_sentence} again with open_tools, and use the tool of the connection that reaches what the person named.
    TEXT
  end

  def self.changes(seen, now)
    removed = (seen.keys - now.keys).map { |id| "#{seen[id]['name']} was removed, so its tools are gone." }
    added = (now.keys - seen.keys).map { |id| connected(now[id]) }
    altered = (now.keys & seen.keys).flat_map { |id| altered(seen[id], now[id]) }
    added + altered + removed
  end

  def self.connected(state)
    tools = state["tools"]
    reaching = ", reaching #{state['reach']}" if state["reach"]
    switched = tools.any? ? ", with #{tools.to_sentence} switched on" : ", with none of its tools switched on yet"
    "#{state['name']} was connected#{reaching}#{switched}."
  end

  def self.altered(before, after)
    name = after["name"]
    lines = []
    lines << "#{before['name']} is now called #{name}." if before["name"] != name
    lines << (after["on"] ? "#{name} was switched back on." : "#{name} was switched off, so none of its tools can be used.") if before["on"] != after["on"]
    lines << "#{name} now reaches #{after['reach'] || 'nothing Firefight can name'}." if before["reach"] != after["reach"]
    on = after["tools"] - before["tools"]
    off = before["tools"] - after["tools"]
    lines << "#{name} had #{on.to_sentence} switched on." if on.any?
    lines << "#{name} had #{off.to_sentence} switched off, so you no longer hold #{off.one? ? 'it' : 'them'}." if off.any?
    lines
  end

  # Forgets remembered tools the catalog no longer has, and remembers a connection's newly switched on tools when the
  # agent had opened their group, returning those it can call now.
  def self.refresh_found_tools!(agent_run, chat, seen, now)
    catalog = Chat::Tools.catalog(agent_run)
    names = catalog.map(&:name).to_set
    kept = chat.found_tool_names.select { |name| names.include?(name) }
    chat.update!(found_tool_names: kept) if kept != chat.found_tool_names

    by_name = catalog.index_by(&:name)
    opened = kept.filter_map { |name| by_name[name]&.group }.to_set
    fresh = now.flat_map { |id, state| state["tools"] - seen.dig(id, "tools").to_a }
    offered = fresh.filter_map { |name| by_name[name] }.select { |entry| entry.tool && opened.include?(entry.group) }.map(&:tool)
    chat.remember_found_tools!(offered.map(&:name))
    offered
  end
  private_class_method :note, :changes, :connected, :altered, :refresh_found_tools!
end
