module Integrations
  module SourceLinks
    # A Datadog log search links to the Log Explorer showing the same query over the same time, on the site the
    # connection reaches. Datadog's documentation gives the site addresses (getting_started/site) and the Explorer's
    # query, from_ts and to_ts parameters. Spans and error tracking get no link, since Datadog documents no address
    # for them that takes a query.
    class Datadog
      PROVIDER = Capabilities::Datadog::PROVIDER_KEY
      NAME = "Datadog".freeze
      SEARCH_LOGS = Capabilities::Datadog::TOOLS.fetch(Capabilities::LOGS)
      # The site a connection reaches, from its server's host: mcp.<site>. A site that is a bare domain is served at app.
      BARE_SITES = %w[datadoghq.com datadoghq.eu ddog-gov.com].freeze
      MCP_HOST = /\Amcp\.(?<site>[a-z0-9.-]+)\z/
      RELATIVE = /\A#{Capabilities::Datadog::NOW}(?:-(?<minutes>\d+)m)?\z/o

      def initialize(integration)
        @integration = integration
      end

      def link(tool_name:, arguments:, text: "")
        return unless tool_name == SEARCH_LOGS

        host = app_host
        asked = arguments.to_h.stringify_keys
        times = Capabilities::Datadog::RANGE.filter_map { |name| asked[name] if asked[name].is_a?(Hash) }.first || asked
        from = millis(Capabilities::Datadog::START.filter_map { |name| times[name] }.first)
        to = millis(Capabilities::Datadog::FINISH.filter_map { |name| times[name] }.first)
        return unless host && from && to

        query = [ ("service:#{asked['service']}" if asked["service"].present?), asked["query"].presence ].compact.join(" ")
        Telemetry::Link.new(provider: NAME, url: "https://#{host}/logs?#{{ query: query, from_ts: from, to_ts: to }.to_query}")
      end

      private

      def app_host
        site = URI.parse(@integration.settings.to_h["server_url"].to_s).host.to_s[MCP_HOST, :site]
        return unless site

        BARE_SITES.include?(site) ? "app.#{site}" : site
      rescue URI::InvalidURIError
        nil
      end

      # Datadog's relative time (now, now-15m) is read against now, so the link shows what the call read.
      def millis(value)
        relative = value.to_s.match(RELATIVE)
        time = relative ? Time.current - relative[:minutes].to_i.minutes : Telemetry.parse_time(value)
        (time.to_f * 1000).to_i if time
      end
    end
  end
end
