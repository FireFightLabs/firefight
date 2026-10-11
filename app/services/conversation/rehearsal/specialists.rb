# The specialists of a replayed chat, asked the way a live chat asks them (Chat::Specialists::Live), over the
# scenario's own tools: a connected tool's kind comes from its provider in the registry, a capability's from its name.
# Each specialist reads through the scenario's world like Halon does, only reads, and a change it proposes is opened in
# Halon's replay as open_tools would open it. Specialists run at once on threads of their own, so every call through the
# world is taken one at a time.
class Conversation::Rehearsal::Specialists
  # Said to a specialist that calls a general tool in a way that would change something.
  ONLY_READS = "Not run. A specialist only reads, so put this change in proposed_changes for Halon to decide on.".freeze

  # recorded builds a scenario tool for a chat (Conversation::Rehearsal#recorded), and open makes named tools callable
  # in Halon's replay and returns their definitions.
  def initialize(bench_case, recorded:, open:)
    @case = bench_case
    @recorded = recorded
    @open = open
    @lock = Mutex.new
  end

  # The kind of system a connected tool belongs to by its provider, or nil for a capability, Firefight's own or one no
  # specialist reads.
  def self.domain_of(definition) = Chat::Specialists.of_provider(definition.source)

  # A connected tool that only reads and whose kind a specialist reads is the specialist's, never Halon's.
  def self.reserved?(definition) = definition.reads && definition.reads_when.blank? && domain_of(definition).present?

  def views
    @views ||= Chat::Specialists::DOMAINS.map do |domain|
      reading = @case.tools.select { |definition| self.class.domain_of(definition) == domain.key && reads?(definition) }
      connections = reading.map { |definition| IntegrationProvider.find(definition.source)&.name || definition.source }.uniq
      Chat::Specialists::View.new(domain: domain, state: reading.any? ? Chat::Tools::STATE_READY : Chat::Tools::STATE_NOT_CONNECTED, connections: connections)
    end
  end

  def tools(agent, domain)
    held = members(domain).select { |definition| reads?(definition) }.map { |definition| Reading.new(@recorded.call(definition, agent.chat), definition, @lock) }
    held + [ Chat::Tools::ReadResult.new(agent) ]
  end

  def changes(_agent, domain)
    members(domain).reject { |definition| definition.reads && definition.reads_when.blank? }.map do |definition|
      Chat::Specialists::Change.new(name: definition.name, line: Chat::Tools.clean(definition.description, Chat::Tools::ONE_LINE))
    end
  end

  def load(name)
    definition = @case.tool(name)
    return Chat::Specialists::Loaded.new(name: name, said: "No tool called #{name} is in this workspace.") unless definition

    @open.call([ name ])
    Chat::Specialists::Loaded.new(name: name, said: "#{name} is now in your hands.")
  end

  # A scenario tool as a specialist holds it: answered from the world, one call at a time across the specialists, and
  # never a change. It never asks the person, since a specialist has nobody to ask.
  class Reading < RubyLLM::Tool
    def initialize(tool, definition, lock)
      super()
      @tool = tool
      @definition = definition
      @lock = lock
    end

    def name = @definition.name

    def description = @definition.description

    def parameters_schema = @definition.parameters.deep_stringify_keys

    def call(tool_call: nil, **arguments)
      return ONLY_READS unless @definition.reads?(Conversation::Rehearsal.asked(arguments))

      @lock.synchronize { @tool.call(tool_call: tool_call, **arguments) }
    end
  end

  private

  # A connected tool of this kind, or a capability or Firefight tool that helps it.
  def members(domain)
    @case.tools.select do |definition|
      kind = self.class.domain_of(definition)
      kind ? kind == domain.key : Chat::Specialists.helping(definition.name).include?(domain.key)
    end
  end

  def reads?(definition) = definition.reads || definition.reads_when.present?
end
