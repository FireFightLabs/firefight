module Integrations
  module Capabilities
    # OpenStatus checks addresses from outside, so it answers how a hostname on the map stands, or a resource the map says
    # serves one, from the monitor that checks it, region by region, through get_monitor_status. The monitors are the
    # ones its health check listed (HealthProbes::Openstatus). The tool and its answer ({monitorId, regions: [{region,
    # status}]}, status active, degraded or error) are from openstatusHQ/openstatus
    # (packages/services/src/agent-tools/monitor.ts).
    module Openstatus
      extend Adapter

      PROVIDER_KEY = "openstatus".freeze
      NAME = "OpenStatus".freeze
      WATCHED = Adapter::ENDPOINT_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { STATUS => WATCHED }.freeze
      TOOLS = { STATUS => "get_monitor_status" }.freeze
      # The monitor tools reach every monitor in the workspace, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze
      MONITOR_ID = "monitorId".freeze

      def self.subject(name) = "the hostnames on the map that #{name} monitors, and the services that serve them"

      # A connection answers only once its health check listed the monitors.
      def self.reaches?(settings, _key) = HealthProbes::Openstatus.monitors(settings).any?

      def self.route(_key, resource, _given, tool:, settings: nil)
        monitors = Monitors.watching(resource, HealthProbes::Openstatus.monitors(settings))
        raise Unroutable, "No OpenStatus monitor checks #{resource.name} or a hostname the map says it serves. list_monitors shows what OpenStatus checks." if monitors.empty?

        monitor, *others = monitors.sort_by { |each| each["id"].to_i }
        Route.new(tool_name: TOOLS.fetch(STATUS), arguments: Answers.known!(tool, { MONITOR_ID => monitor["id"] }, NAME),
                  present: ->(result) { Answers.read(result, PROVIDER_KEY) { |body| status_result(monitor, others, body, result) } })
      end

      def self.status_result(monitor, others, body, result)
        regions = Array(body["regions"]).select { |region| region.is_a?(Hash) && region["region"] }
        return if regions.empty?

        failing = regions.reject { |region| region["status"] == "active" }
        lines = regions.map { |region| "#{region['region']}: #{region['status']}" }
        summary = failing.empty? ? "up in every region it checks from" : "#{failing.map { |region| region['status'] }.tally.map { |status, count| "#{status} in #{count}" }.join(', ')} of #{regions.size} regions"
        more = others.any? ? "\nOther monitors on the same hostname: #{others.map { |each| "#{each['name']} (#{each['id']})" }.join(', ')}." : ""
        Answers.presented(result, "OpenStatus monitor #{monitor['name']} (#{monitor['url']}) is #{summary}. get_monitor_summary gives the last day's " \
                                  "checks and latency.\n#{lines.join("\n")}#{more}")
      end

      private_class_method :status_result
    end
  end
end
