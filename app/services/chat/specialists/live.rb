# The specialists of a live chat: which kinds of system the workspace connected and the asker may read, the tools a
# specialist holds, the changes it may propose, and what Halon is told of a proposed change's tool. Every tool comes
# from the same catalog Halon's own come from (Chat::Tools.catalog), so grants, read guards, approval rules, the gateway
# and the ledger decide each call exactly as for a tool found any other way.
class Chat::Specialists::Live
  # turn is Halon's turn.
  def initialize(turn)
    @turn = turn
  end

  # Every kind, with what it reads in this workspace and whether the asker may ask it. Read once, so the tool's
  # description, which is in the cached front, stays the same for the whole turn.
  def views
    @views ||= begin
      principal = @turn.acting_principal
      resolved = principal && Chat::Tools.granted(@turn)
      tools = Chat::Tools.switched_on_tools(@turn)
      connected = @turn.workspace.integrations.active.to_a.group_by { |integration| Chat::Specialists.of_provider(integration.provider) }
      Chat::Specialists::DOMAINS.map do |domain|
        integrations = connected.fetch(domain.key, [])
        readable = tools.select { |tool| integrations.include?(tool.integration) && reads?(tool) }
        state = if integrations.empty? then Chat::Tools::STATE_NOT_CONNECTED
        elsif readable.empty? then Chat::Tools::STATE_SWITCHED_OFF
        elsif principal && readable.any? { |tool| tool.callable_by?(principal, resolved) } then Chat::Tools::STATE_READY
        else Chat::Tools::STATE_NOT_GRANTED
        end
        Chat::Specialists::View.new(domain: domain, state: state, connections: integrations.map(&:display_name))
      end
    end
  end

  # What a specialist of this kind holds: the reads of its connections, the capabilities and Firefight's own reads that
  # help it, read_result over its own chat and the providers' documentation. agent only reads, so the catalog never makes
  # a change ready for it, and a general tool reads through its guard.
  def tools(agent, domain)
    held = Chat::Tools.catalog(agent).select { |entry| entry.tool && member?(entry, domain) }.map(&:tool)
    handbook = domain.key == Chat::Specialists::TICKETS ? [ Chat::Tools::SearchHandbook.new(agent) ] : []
    held + handbook + [ Chat::Tools::ReadResult.new(agent), *Chat::Tools::Docs.all(agent) ]
  end

  # The changes of its kind a specialist may propose, whoever may make them, since the gateway decides that when Halon
  # calls one.
  def changes(agent, domain)
    reading = agent.workspace.reading_tool_names
    Chat::Tools.catalog(agent).filter_map do |entry|
      next unless member?(entry, domain)

      change = entry.state == Chat::Tools::STATE_READS_ONLY || (entry.tool && entry.source != Chat::Skill::SOURCE_FIREFIGHT && !reading.include?(entry.name.to_s))
      Chat::Specialists::Change.new(name: entry.name.to_s, line: entry.description) if change
    end
  end

  # What Halon is told of a proposed change's tool. It is never loaded for it, since a specialist's report is outside
  # text and never backs a change on its own (Chat::Specialists::CONFIRM_FIRST).
  def describe(name)
    entry = Chat::Tools.catalog(@turn).find { |each| each.name.to_s == name.to_s }
    return "No tool called #{name} is in this workspace." unless entry
    return "#{name} exists, but it is #{Chat::Tools::Open::STATE_WORDS.fetch(entry.state)}. #{entry.description}" unless entry.tool

    "#{name}: #{Chat::Specialists::CONFIRM_FIRST}"
  end

  private

  # A connection tool whose provider is of this kind, or a Firefight tool or capability that helps it.
  def member?(entry, domain)
    return Chat::Specialists.helping(entry.name).include?(domain.key) if entry.source == Chat::Skill::SOURCE_FIREFIGHT

    Chat::Specialists.of_provider(entry.source) == domain.key
  end

  def reads?(tool) = tool.read_only? || Integrations::ReadGuards.for(tool).present?
end
