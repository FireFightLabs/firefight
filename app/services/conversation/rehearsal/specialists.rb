# The specialists of a replayed chat, asked the way a live chat asks them (Chat::Specialists::Live), over the
# scenario's own tools: a connected tool's kind comes from its provider in the registry, a capability's from its name.
# Each specialist reads through the scenario's world like Halon does and only reads, and a change it proposes is
# described to Halon as live, never loaded for it. Specialists run at once on threads of their own, so every call
# through the world is taken one at a time.
class Conversation::Rehearsal::Specialists
  # Said to a specialist that calls a general tool in a way that would change something.
  ONLY_READS = "Not run. A specialist only reads, so put this change in proposed_changes for Halon to decide on.".freeze

  # recorded builds a scenario tool for a chat (Conversation::Rehearsal#recorded).
  def initialize(bench_case, recorded:)
    @case = bench_case
    @recorded = recorded
    @lock = Mutex.new
  end

  # The kind of system a connected tool belongs to by its provider, or nil for a capability, Firefight's own or one no
  # specialist reads.
  def self.domain_of(definition) = Chat::Specialists.of_provider(definition.source)

  # A connected tool that only reads and whose kind a specialist reads is the specialist's, never Halon's.
  def self.reserved?(definition) = definition.reads && definition.reads_when.blank? && domain_of(definition).present?

  # The read guard of a connected tool that both reads and changes and whose provider can show a call reads, with the
  # shape it reads in, as live (Integrations::ReadGuards), or nil. A tool the scenario already says reads by its
  # arguments (reads_when) is read that way.
  def self.guard_of(definition)
    return if definition.reads || definition.reads_when.present? || !definition.outside?

    guard = Integrations::Provider.for(definition.source).read_guard
    guard if guard&.guards?(handle_of(definition)) && guard.schema.present?
  end

  def self.handle_of(definition) = definition.name.delete_prefix("#{definition.source}_")

  def views
    @views ||= Chat::Specialists::DOMAINS.map do |domain|
      reading = @case.tools.select { |definition| self.class.domain_of(definition) == domain.key && reads?(definition) }
      connections = reading.map { |definition| IntegrationProvider.find(definition.source)&.name || definition.source }.uniq
      Chat::Specialists::View.new(domain: domain, state: reading.any? ? Chat::Tools::STATE_READY : Chat::Tools::STATE_NOT_CONNECTED, connections: connections)
    end
  end

  def tools(agent, domain)
    held = members(domain).select { |definition| reads?(definition) }.map do |definition|
      guard = self.class.guard_of(definition)
      tool = @recorded.call(definition, agent.chat)
      guard ? Guarded.new(tool, definition, guard, @lock) : Reading.new(tool, definition, @lock)
    end
    held + [ Chat::Tools::ReadResult.new(agent) ]
  end

  def changes(_agent, domain)
    members(domain).reject { |definition| definition.reads && definition.reads_when.blank? }.map do |definition|
      Chat::Specialists::Change.new(name: definition.name, line: Chat::Tools.clean(definition.description, Chat::Tools::ONE_LINE))
    end
  end

  def describe(name)
    return "No tool called #{name} is in this workspace." unless @case.tool(name)

    "#{name}: #{Chat::Specialists::CONFIRM_FIRST}"
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

  # A general tool as a specialist holds it where its provider's read guard can show a call reads: in the guard's own
  # reading shape, which Firefight turns into the tool's own call as live (Integrations::ReadGuards), so a specialist
  # reads through it and never changes anything.
  class Guarded < RubyLLM::Tool
    def initialize(tool, definition, guard, lock)
      super()
      @tool = tool
      @definition = definition
      @guard = guard
      @lock = lock
    end

    def name = @definition.name

    def description = [ @definition.description, (@guard::DESCRIPTION if @guard.const_defined?(:DESCRIPTION)) ].compact.join(" ")

    def parameters_schema = @guard.schema

    def call(tool_call: nil, **arguments)
      handle = Conversation::Rehearsal::Specialists.handle_of(@definition)
      given = @guard.reading(handle, arguments.stringify_keys)
      return ONLY_READS unless @guard.reads?(handle, given)

      @lock.synchronize { @tool.call(tool_call: tool_call, **given) }
    rescue Integrations::ReadGuards::Refused, Integrations::PolicyRefusal => refused
      refused.message
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

  def reads?(definition) = definition.reads || definition.reads_when.present? || self.class.guard_of(definition).present?
end
