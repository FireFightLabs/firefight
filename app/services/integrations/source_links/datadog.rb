module Integrations
  module SourceLinks
    # A Datadog log search links to the Log Explorer showing the same query over the same time, on the site of the
    # region the connection was made in (the registry's regions, from Datadog's getting_started/site). Datadog's
    # documentation gives the Explorer's query, from_ts and to_ts parameters. Spans and error tracking get no link,
    # since Datadog documents no address for them that takes a query. A connection in no region Firefight knows gets no
    # link rather than a guessed site.
    class Datadog
      NAME = "Datadog".freeze
      SEARCH_LOGS = Capabilities::Datadog::TOOLS.fetch(Capabilities::LOGS)
      RELATIVE = /\A#{Capabilities::Datadog::NOW}(?:-(?<minutes>\d+)m)?\z/o

      def initialize(settings)
        @site = settings.site
      end

      def link(tool_name:, arguments:, text: "")
        return unless tool_name == SEARCH_LOGS

        asked = arguments.to_h.stringify_keys
        times = Capabilities::Datadog::RANGE.filter_map { |name| asked[name] if asked[name].is_a?(Hash) }.first || asked
        from = millis(Capabilities::Datadog::START.filter_map { |name| times[name] }.first)
        to = millis(Capabilities::Datadog::FINISH.filter_map { |name| times[name] }.first)
        return unless @site && from && to

        query = [ ("service:#{asked['service']}" if asked["service"].present?), asked["query"].presence ].compact.join(" ")
        Telemetry::Link.new(provider: NAME, url: "#{@site.chomp('/')}/logs?#{{ query: query, from_ts: from, to_ts: to }.to_query}")
      end

      private

      # Datadog's relative time (now, now-15m) is read against now, so the link shows what the call read.
      def millis(value)
        relative = value.to_s.match(RELATIVE)
        time = relative ? Time.current - relative[:minutes].to_i.minutes : Telemetry.parse_time(value)
        (time.to_f * 1000).to_i if time
      end
    end
  end
end
