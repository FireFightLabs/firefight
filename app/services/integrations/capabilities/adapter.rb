module Integrations
  module Capabilities
    # What every provider's adapter declares: the kinds of resource each capability covers, the provider tool each one
    # runs as, and the provider tools it answers one to one. route is the adapter's own.
    module Adapter
      def supports?(key, kind) = self::SUPPORTS.fetch(key, []).include?(kind)

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
