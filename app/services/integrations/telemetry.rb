module Integrations
  # Provider-neutral shapes for telemetry tools. A provider pack turns its API's answers into these, and this module
  # writes the text the model reads and the chart data a person sees. A new telemetry provider only maps its API.
  module Telemetry
    # Where charts travel in a tool result, next to the text. MCP calls this part of a result structuredContent.
    STRUCTURED = "structuredContent".freeze
    CHARTS = "charts".freeze

    LOG_LINE_LIMIT = 500
    LOG_CELL_LIMIT = 1_000
    SERIES_LIMIT = 8

    LogLine = Data.define(:at, :source, :text)
    # points are [time, value] pairs in time order. label tells series of one metric apart, such as a container.
    Series = Data.define(:label, :points)
    # link is the chart's page on the provider, where the full, live chart is.
    Chart = Data.define(:title, :unit, :series, :from, :to, :link) do
      def initialize(link: nil, **) = super

      # One line per series, the same numbers the model reads, for places that show a chart as a caption.
      def summary
        lines = series.first(SERIES_LIMIT).map { |each| "#{each.label}: #{Telemetry.summary(each.points)}" }
        lines << Telemetry.left_out(series.size) if series.size > SERIES_LIMIT
        lines.join("\n")
      end

      def to_h
        {
          "title" => title, "unit" => unit, "from" => from.utc.iso8601, "to" => to.utc.iso8601, "link" => link, "summary" => summary,
          "series" => series.first(SERIES_LIMIT).map { |each| { "label" => each.label, "points" => each.points.map { |at, value| [ at.utc.iso8601, value ] } } }
        }
      end
    end

    def self.logs_text(lines, asked:)
      return "No log lines matched #{asked}." if lines.empty?

      shown = lines.first(LOG_LINE_LIMIT).map do |line|
        "#{line.at.utc.iso8601} #{line.source} #{line.text.to_s.strip.truncate(LOG_CELL_LIMIT)}".squish
      end
      "#{lines.size} log lines for #{asked}, newest first.\n#{shown.join("\n")}"
    end

    # The model reads numbers, a person reads the chart. Each series is summed up in one line.
    def self.charts_text(charts)
      return "No data points in that range." if charts.all? { |chart| chart.series.all? { |each| each.points.empty? } }

      charts.map do |chart|
        lines = chart.series.first(SERIES_LIMIT).map { |each| "  #{each.label}: #{summary(each.points)}" }
        lines << "  #{left_out(chart.series.size)}" if chart.series.size > SERIES_LIMIT
        "#{chart.title} (#{chart.unit}), #{chart.from.utc.iso8601} to #{chart.to.utc.iso8601}\n#{lines.join("\n")}"
      end.join("\n")
    end

    def self.summary(points)
      return "no data" if points.empty?

      values = points.map(&:last)
      peak_at, peak = points.max_by(&:last)
      "min #{round(values.min)}, avg #{round(values.sum / values.size)}, max #{round(peak)} at #{peak_at.utc.iso8601}, " \
        "latest #{round(values.last)} (#{values.size} points)"
    end

    def self.left_out(total) = "#{total - SERIES_LIMIT} more series not shown, only the first #{SERIES_LIMIT} are kept"

    def self.result(text, charts: [])
      result = { "content" => [ { "type" => "text", "text" => text } ] }
      result[STRUCTURED] = { CHARTS => charts.map(&:to_h) } if charts.any?
      result
    end

    # The time range a tool was asked for: minutes back from now, or an explicit start and end.
    def self.range(arguments, default_minutes:, max_minutes:)
      ended = parse_time(arguments["end"]) || Time.current
      started = parse_time(arguments["start"])
      minutes = arguments["minutes"].to_i.positive? ? arguments["minutes"].to_i : default_minutes
      started ||= ended - minutes.minutes
      started = [ started, ended - max_minutes.minutes ].max
      [ started, ended ]
    end

    def self.parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    def self.round(value) = value.to_f.round(value.to_f.abs < 10 ? 3 : 1)
  end
end
