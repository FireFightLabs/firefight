module Integrations
  module SourceLinks
    # A Logfire query links to Logfire's live view of the project the connection reads, filtered to the service the
    # query names, over the same time. The project's address is the one its health check read (HealthProbes::Logfire),
    # kept only while it is on the app of the connection's region (settings.site), and the live view's q, since
    # and until parameters are from Pydantic's own skill (pydantic/skills, plugins/logfire/skills/logfire-ui/SKILL.md).
    # Without the address there is no link.
    class Logfire
      NAME = "Logfire".freeze
      SERVICE = /\bservice_name\s*(?:=|IN\s*\()\s*'((?:[^']|'')*)'\s*\)?/i

      def initialize(settings)
        project = HealthProbes::Logfire.address(settings)
        site = settings&.site
        @project = project if site && project.to_s.start_with?("#{site.chomp('/')}/")
      end

      def link(tool_name:, arguments:, text: "")
        project = @project
        asked = arguments.to_h.stringify_keys
        return unless tool_name == Capabilities::Logfire::QUERY_RUN && project

        services = asked["query"].to_s.scan(SERVICE).flatten.uniq
        filter = { q: ("service_name = '#{services.first}'" if services.one?), since: time(asked["min_timestamp"]), until: time(asked["max_timestamp"]) }.compact
        Telemetry::Link.new(provider: NAME, url: filter.empty? ? project : "#{project}?#{filter.to_query}")
      end

      private

      def time(value) = Telemetry.parse_time(value)&.utc&.iso8601
    end
  end
end
