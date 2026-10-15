# Where a chart sits in what Halon wrote: {{chart:3f9a1c2e}}, the first eight characters of the chart's id. The tool
# result that drew a chart names its marker, Halon writes it where the chart belongs, and the dashboard draws the chart
# there. Every other place that reads the words, Slack, MCP, the API and previews among them, reads them without it.
module Chat::Chart::Marker
  PATTERN = /`?\{\{\s*chart:\s*([0-9a-f]{8})\s*\}\}`?/i
  # A line holding only markers goes with its line break, so no blank gap is left where a chart was.
  ALONE = /^[ \t]*(?:#{PATTERN}[ \t]*)+(?:\r?\n|\z)/i
  INLINE = /[ \t]*#{PATTERN}/i
  # The start of a marker still being written, which a stream holds back at the end of the words so far.
  ARRIVING = /[ \t]*`?\{(?:\{\s*(?:c(?:h(?:a(?:r(?:t(?::\s*[0-9a-f]{0,8}\s*\}?)?)?)?)?)?)?)?/i

  NOTE = "Charts drawn for the person, each placed in your answer by its marker:".freeze

  def self.for(chart) = "{{chart:#{chart.handle}}}"

  def self.handles_in(text) = text.to_s.scan(PATTERN).flatten.map(&:downcase).uniq

  def self.strip(text)
    return text unless text.to_s.match?(PATTERN)

    text.gsub(ALONE, "").gsub(INLINE, "").gsub(/\n{3,}/, "\n\n").strip
  end

  # What the model is told about the charts a call drew, so it can place them. nil when it drew none.
  def self.note(charts)
    return if charts.blank?

    [ NOTE, *charts.map { |chart| "#{self.for(chart)} #{chart.title}" } ].join("\n")
  end
end
