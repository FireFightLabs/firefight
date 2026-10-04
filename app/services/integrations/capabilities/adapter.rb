module Integrations
  module Capabilities
    # What every provider's adapter declares: the kinds of resource each capability covers (SUPPORTS for what it runs,
    # OBSERVES for what it watches that others run), the provider tool each one runs as (TOOLS), and the provider tools it
    # answers one to one (WRAPPED). route is the adapter's own:
    #
    #   route(key, resource, given, tool:, settings:)  a Route, or raises Unroutable with words an agent can act on
    #
    # tool is the connection's Integration::Tool, nil when only a refusal is wanted, and settings the connection's
    # ConnectionSettings, for what it was set up with, its region and what its health check learned.
    module Adapter
      def supports?(key, kind) = self::SUPPORTS.fetch(key, []).include?(kind)

      # An observability tool watches resources others run, by capability and kind. A platform watches nothing.
      def observes?(key, kind) = observed.fetch(key, []).include?(kind)

      def observed = const_defined?(:OBSERVES, false) ? self::OBSERVES : {}

      # The capabilities this provider answers for some kind of resource, in the order they are listed.
      def capabilities = SPECS.keys.select { |key| self::SUPPORTS.key?(key) || observed.key?(key) }

      def tool_for(key) = self::TOOLS[key]

      # Whether it can take what was asked. A platform takes everything its route does. An observability tool that
      # cannot is passed over for the platform, unless it was named.
      def accepts?(_key, _given, settings: nil) = true

      # Whether a connection knows enough to answer a capability at all, such as which of its datasources holds logs.
      # One that does not is passed over, so the platform answers as it did before the tool was connected.
      def reaches?(_settings, _key) = true

      # Why it would not take what was asked, in the words its route raises.
      def route_refusal(key, resource, given, settings: nil)
        route(key, resource, given, tool: nil, settings: settings)
        nil
      rescue Unroutable => error
        error.message
      end

      # What Halon answers for through it, in the sentence a person reads in the provider's details. A platform answers
      # for what it runs, an observability tool for the services it watches.
      def subject(name)
        watches = observed.any? && self::SUPPORTS.empty?
        watches ? "the services on the map that #{name} watches, by their name in #{name}" : "anything #{name} runs"
      end

      # How a capability reads in that sentence.
      def phrase(key) = PHRASES.fetch(key)

      def runs?(key, tool_name) = self::TOOLS[key] == tool_name

      def wraps?(tool_name) = self::WRAPPED.include?(tool_name)

      def target(given)
        to = given["to"].to_s.strip
        raise Unroutable, "Say what to roll back to, by the id recent_deploys shows." if to.empty?

        to
      end

      def instances(given)
        count = Integer(given["instances"], exception: false)
        raise Unroutable, "instances must be a whole number, 0 or more." unless count && count >= 0

        count
      end

      def metric_names(given, mapping, provider)
        asked = Array(given["metrics"]).map(&:to_s).uniq
        missing = asked - mapping.keys
        if missing.any?
          raise Unroutable, "#{provider} does not keep #{missing.join(', ')} for this resource. It keeps #{mapping.keys.join(', ')}."
        end

        asked.map { |name| mapping.fetch(name) }
      end
    end
  end
end
