module Integrations
  module Capabilities
    # Better Stack checks addresses from outside, so it answers how a hostname on the map stands, or a resource the map
    # says serves one, from the uptime monitor that checks it, through its monitor tool. The monitors are the ones its
    # health check listed (HealthProbes::Betterstack). The tool's name is from Better Stack's own skill
    # (BetterStackHQ/claude-plugin, skills/investigate-incident/SKILL.md). Better Stack publishes its parameters only
    # from its server, so the monitor's id goes in whichever of monitor_id or id the connected tool reports, and its
    # answer reaches the agent as it came.
    module Betterstack
      extend Adapter

      PROVIDER_KEY = "betterstack".freeze
      NAME = "Better Stack".freeze
      WATCHED = Adapter::ENDPOINT_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { STATUS => WATCHED }.freeze
      TOOLS = { STATUS => "monitor" }.freeze
      # Better Stack's tools reach every monitor, incident and source of the team, far beyond the map, so they stay offered.
      WRAPPED = [].freeze
      ID = %w[monitor_id id].freeze

      def self.subject(name) = "the hostnames on the map that #{name} monitors, and the services that serve them"

      # A connection answers only once its health check listed the monitors.
      def self.reaches?(settings, _key) = HealthProbes::Betterstack.monitors(settings).any?

      def self.route(_key, resource, _given, tool:, settings: nil)
        monitors = Monitors.watching(resource, HealthProbes::Betterstack.monitors(settings))
        raise Unroutable, "No Better Stack monitor checks #{resource.name} or a hostname the map says it serves. monitors lists what Better Stack checks." if monitors.empty?

        id = Answers.named(tool, ID)
        raise Unroutable, "Better Stack's monitor tool takes its monitor in a way Firefight does not know, so ask it with Better Stack's own tools." unless id

        monitor, *others = monitors.sort_by { |each| each["id"].to_i }
        Route.new(tool_name: TOOLS.fetch(STATUS), arguments: { id => monitor["id"] },
                  present: (->(result) { result.merge("content" => Array(result["content"]) + [ { "type" => "text", "text" => also(others) } ]) } if others.any?))
      end

      def self.also(others) = "Other Better Stack monitors on the same hostname: #{others.map { |each| "#{each['name']} (#{each['id']})" }.join(', ')}."

      private_class_method :also
    end
  end
end
