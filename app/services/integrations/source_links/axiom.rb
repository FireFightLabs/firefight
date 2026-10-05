module Integrations
  module SourceLinks
    # An Axiom query links to Axiom's query page with the same APL over the same time, in the organization the connection
    # reads, which the connect form asks for. The address is the one Axiom's own skill builds
    # (axiomhq/skills, skills/sre/scripts/axiom-link), <site>/<org>/query with initForm, a JSON form holding apl and
    # queryOptions with startTime and endTime, on the provider's site (settings.site). Without the organization there is
    # no link.
    class Axiom
      NAME = "Axiom".freeze
      ORG_ID = "org_id".freeze
      ORGANIZATION = /\A[A-Za-z0-9._-]+\z/
      RELATIVE = /\Anow(?:-(?<minutes>\d+)m)?\z/

      def initialize(settings)
        @organization = settings&.field(ORG_ID).to_s.strip
        @site = settings&.site
      end

      def link(tool_name:, arguments:, text: "")
        organization = @organization
        asked = arguments.to_h.stringify_keys
        apl = Capabilities::Axiom::QUERY.filter_map { |name| asked[name].presence }.first
        return unless tool_name == Capabilities::Axiom::QUERY_DATASET && @site && organization.match?(ORGANIZATION) && apl.is_a?(String)

        started = time(Capabilities::Axiom::START.filter_map { |name| asked[name] }.first)
        ended = time(Capabilities::Axiom::FINISH.filter_map { |name| asked[name] }.first)
        options = started && ended ? { startTime: started.iso8601, endTime: ended.iso8601 } : {}
        Telemetry::Link.new(provider: NAME, url: "#{@site.chomp('/')}/#{organization}/query?#{{ initForm: { apl: apl, queryOptions: options }.to_json }.to_query}")
      end

      private

      # Axiom's relative time (now, now-15m) is read against now, so the link shows what the call read.
      def time(value)
        relative = value.to_s.match(RELATIVE)
        (relative ? Time.current - relative[:minutes].to_i.minutes : Telemetry.parse_time(value))&.utc
      end
    end
  end
end
