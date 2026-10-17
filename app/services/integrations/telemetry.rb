module Integrations
  # Provider-neutral shapes for telemetry tools. A provider pack turns its API's answers into these, and this module
  # writes the text the model reads and the chart data a person sees. A new telemetry provider only maps its API.
  module Telemetry
    # The key a tool result keeps its charts under, next to its text. MCP names this part of a result structuredContent.
    STRUCTURED = "structuredContent".freeze
    CHARTS = "charts".freeze
    # The provider's answer as its API gave it, for a call its own command line tool made in Halon's terminal
    # (NativePack#relayed?). The model reads the text, never this.
    RELAYED = "relayed".freeze
    # Values a change's answer names for what it made, such as a comment's id, which the call that puts it back is built
    # from (SafeChanges.inverse). The model reads the text, never this.
    FACTS = "facts".freeze

    LOG_LINE_LIMIT = 500
    LOG_CELL_LIMIT = 1_000
    SERIES_LIMIT = 8

    LogLine = Data.define(:at, :source, :text)
    # Where the person sees what a tool returned, on the provider itself, opened on the same filter and time range when
    # the provider's address can carry them. An answer about logs or metrics that cannot be checked at the source is
    # worth little, so a result names its link or says it has none.
    Link = Data.define(:provider, :url)
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

    # limit is how many lines the provider was asked for. Reaching it means older lines were not returned, and the text
    # says so, so the model narrows the range or filters rather than taking the lines as all there were.
    # The level a log line carries in a field of its own, as structured logs write it: "level":"warn" in JSON, level=error
    # in logfmt, or severity, levelname and lvl the same way.
    LEVEL_FIELD = /["']?\b(?:levelname|severity|level|lvl)["']?\s*[:=]\s*["']?([A-Za-z]+)/i
    # A provider that keeps the level apart from the text names it where logs_text puts the source.
    LEVEL_WORDS = %w[trace debug info notice warn warning error err fatal critical crit alert emerg emergency panic].freeze
    ERROR_LEVELS = %w[error err fatal critical crit alert emerg emergency panic].freeze
    # A line as logs_text writes it, a time, its source and the text.
    SHARED_LINE = /\A\d{4}-\d{2}-\d{2}T\S+\s+(\S+)\s/

    # The levels the lines of a logs answer carry, one per line that carries one, lower case.
    def self.levels_in(text)
      text.to_s.lines.filter_map do |line|
        field = line[LEVEL_FIELD, 1]&.downcase
        next field if field && LEVEL_WORDS.include?(field)

        source = line[SHARED_LINE, 1]&.downcase
        source if LEVEL_WORDS.include?(source)
      end
    end

    def self.error_level?(level) = ERROR_LEVELS.include?(level.to_s.downcase)

    def self.logs_text(lines, asked:, limit: LOG_LINE_LIMIT)
      return "No log lines matched #{asked}." if lines.empty?

      shown = lines.first(LOG_LINE_LIMIT).map do |line|
        "#{line.at.utc.iso8601} #{line.source} #{line.text.to_s.strip.truncate(LOG_CELL_LIMIT)}".squish
      end
      cut = lines.size >= limit ? " These are only the newest #{limit}. Older lines in the range were not returned, so narrow the range or filter to see them." : ""
      "#{lines.size} log lines for #{asked}, newest first.#{cut}\n#{shown.join("\n")}"
    end

    # The model reads numbers, a person reads the chart. Each series is summed up in one line.
    def self.charts_text(charts)
      charts.map do |chart|
        next "#{chart.title}: no data in that range. That does not show zero, and can mean the provider does not record it here." if empty?(chart)

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

    # A chart with nothing in it is said in the text and never drawn, so an empty frame never reads as evidence.
    def self.result(text, link:, charts: [], relayed: nil, facts: {})
      text = "#{text}\n#{link_line(link)}" if link
      result = { "content" => [ { "type" => "text", "text" => text } ] }
      drawn = charts.reject { |chart| empty?(chart) }
      structured = { CHARTS => (drawn.map(&:to_h) if drawn.any?), RELAYED => relayed, FACTS => (facts.compact if facts.compact.any?) }.compact
      result[STRUCTURED] = structured if structured.any?
      result
    end

    def self.empty?(chart) = chart.series.all? { |each| each.points.empty? }

    LINK_LINE = "Open this in %<provider>s, and give the person this link with what you found: %<url>s".freeze

    def self.link_line(link) = format(LINK_LINE, provider: link.provider, url: link.url)

    def self.link_line?(text) = text.to_s.start_with?(LINK_LINE.split("%<provider>s").first)

    # The time range a tool was asked for, as minutes back from now or as an explicit start and end.
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
