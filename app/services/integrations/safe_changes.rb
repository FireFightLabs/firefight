module Integrations
  # Which changes are safe for Halon to make without asking, from what each provider declares (the registry's safe_tools),
  # the one fixed call that puts each back (undo_tools), and which change who can reach something or a secret
  # (access_tools), which a person is always asked about. A tool on a remote server counts only through its own
  # provider's list, so a native provider's list never covers a tool of the same name on a server. A capability's
  # change is decided call by call from a live count, since a restart can take down the one copy running and a scale
  # can go down or change the plan.
  module SafeChanges
    RESULT = "result.".freeze
    LITERAL = "=".freeze
    # A scale up is safe only to this many times the live count, and by at most SCALE_STEP_LIMIT instances.
    SCALE_FACTOR = 2
    SCALE_STEP_LIMIT = 10
    # How old a map reading may be and still count as the live count. An older one is read again first.
    LIVE_FOR = 2.minutes

    # The fixed call that puts a change back: the tool on the same connection and the arguments it is sent.
    # capability is the capability Firefight built it for, nil for one the registry declares.
    Inverse = Data.define(:tool, :arguments, :capability) do
      def initialize(capability: nil, **) = super
    end

    def self.tool?(tool) = listed?(tool, :safe_tools)

    # A safe tool whose call outside text could have written, such as a comment's words, which is safe only while
    # nothing from outside has reached the chat (Chat::Tools::Provenance.read_anything_outside?).
    def self.until_outside?(tool) = listed?(tool, :safe_until_outside_tools)

    def self.access?(tool)
      entry = IntegrationProvider.find(tool.integration.provider)
      entry.present? && entry.access_tools.include?(tool.name)
    end

    # Whether the registry declares a fixed undo for a tool, before its call ran.
    def self.declares_undo?(tool)
      entry = entry_of(tool)
      entry.present? && entry.kind == tool.integration.kind && entry.undo_tools.to_h.key?(tool.name)
    end

    # The undo the registry declares for a tool's call, built from the call's own arguments and the values its answer
    # named, or nil when it declares none or a value is missing. Never a tool that changes access, writes rows, stops
    # something or carries a read guard, and always one of the same connection that is switched on.
    def self.inverse(tool, arguments, result)
      entry = entry_of(tool)
      spec = (entry.undo_tools.to_h[tool.name] if entry && entry.kind == tool.integration.kind)
      return mitigation_inverse(tool, arguments) unless spec

      undo = tool.integration.tools.find_by(name: spec["tool"], enabled: true)
      return nil unless undo && inverse_allowed?(undo)

      given = arguments.to_h.stringify_keys
      facts = (result.to_h[Telemetry::STRUCTURED] || {})[Telemetry::FACTS].to_h
      sources = spec["arguments"].to_h.transform_keys(&:to_s).transform_values(&:to_s)
      built = sources.to_h { |name, from| [ name, value_of(from, given, facts) ] }.reject { |_name, value| value.blank? }
      return nil if sources.any? { |name, from| from.start_with?(RESULT) && !built.key?(name) }
      # Something must differ from the call itself, another tool or an argument such as a label to take off, or the undo
      # would do nothing.
      return nil unless undo.name != tool.name || built.any? { |name, _value| sources[name] != name }

      Inverse.new(tool: undo, arguments: built)
    end

    # The undo a general tool's provider builds for one temporary change it made, through the same tool, such as resuming
    # a schedule it paused (Integrations::Mitigations.undo_arguments), or nil when it builds none.
    def self.mitigation_inverse(tool, arguments)
      built = Mitigations.undo_arguments(tool, arguments)
      Inverse.new(tool: tool, arguments: built) if built.present? && tool.enabled? && inverse_allowed?(tool)
    end

    # Whether a tool may be the undo of a change made without asking.
    def self.inverse_allowed?(tool)
      !tool.read_only? && !access?(tool) && Integrations::ReadGuards.for(tool).nil? &&
        (tool.effects & [ Ability::Action::EFFECT_DATA_WRITE, Ability::Action::EFFECT_STOPS ]).empty?
    end

    def self.value_of(from, given, facts)
      return from.delete_prefix(LITERAL) if from.start_with?(LITERAL)
      return facts[from.delete_prefix(RESULT)] if from.start_with?(RESULT)

      given[from]
    end
    private_class_method :value_of

    # A restart of a service that runs more than one copy, by its live count, or a scale up within SCALE_FACTOR and
    # SCALE_STEP_LIMIT of its live count that names no plan. A restart of a database, a machine or a single copy, a scale
    # down, a plan change and a count Firefight could not read fresh all ask, and a rollback always does.
    def self.capability_call?(call, given)
      given = given.to_h.stringify_keys
      case call.spec.key
      when Capabilities::RESTART then call.resource&.kind == ResourceMap::KIND_SERVICE && (live_instances(call) || 0) > 1
      when Capabilities::SCALE then scales_up_safely?(call, given)
      else false
      end
    end

    # The scale back to the live count from before, for a safe scale up. A restart has nothing that puts it back.
    def self.capability_inverse(call, given, workspace:, principal:)
      given = given.to_h.stringify_keys
      return nil unless call.spec.key == Capabilities::SCALE && scales_up_safely?(call, given)

      back = Capabilities.resolve(workspace, Capabilities::SCALE, given.except(Capabilities::PLAN_ARG).merge("instances" => live_instances(call).to_s),
                                  [ call.tool ], principal: principal)
      Inverse.new(tool: call.tool, arguments: back.arguments, capability: Capabilities::SCALE)
    rescue Capabilities::Unroutable
      nil
    end

    # The scale back to the live count from before, for a scale down kept as a temporary change.
    def self.scale_back(call, workspace:, principal:)
      return nil unless call.spec.key == Capabilities::SCALE

      before = live_instances(call)
      return nil unless before

      back = Capabilities.resolve(workspace, Capabilities::SCALE, { "resource" => call.resource&.id.to_s, "instances" => before.to_s }, [ call.tool ],
                                  principal: principal)
      Inverse.new(tool: call.tool, arguments: back.arguments, capability: Capabilities::SCALE)
    rescue Capabilities::Unroutable
      nil
    end

    def self.scales_up_safely?(call, given)
      return false if given[Capabilities::PLAN_ARG].present?

      now = live_instances(call)
      asked = Integer(given["instances"].to_s, exception: false)
      !now.nil? && !asked.nil? && asked > now && asked <= now * SCALE_FACTOR && asked - now <= SCALE_STEP_LIMIT
    end
    private_class_method :scales_up_safely?

    # The resource's count as its connection reports it now, read again through the map when the map's reading is older
    # than LIVE_FOR, or nil when it cannot be read.
    def self.live_instances(call)
      resource = call.resource
      return nil unless resource && call.environment_row

      MapSweep.run!(call.environment_row) && resource.reload if resource.last_seen_at.nil? || resource.last_seen_at < LIVE_FOR.ago
      return nil if resource.removed_at || resource.last_seen_at.nil? || resource.last_seen_at < LIVE_FOR.ago

      Integer(resource.details.to_h["instances"].to_s, exception: false)
    end

    def self.entry_of(tool) = IntegrationProvider.find(tool.integration.provider)
    private_class_method :entry_of

    def self.listed?(tool, list)
      return false if tool.read_only?

      entry = entry_of(tool)
      entry.present? && entry.kind == tool.integration.kind && entry.public_send(list).include?(tool.name)
    end
    private_class_method :listed?
  end
end
