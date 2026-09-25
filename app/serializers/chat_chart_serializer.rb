# A chart a tool returned in a chat, for the chart card under the step that made it.
class ChatChartSerializer < BaseSerializer
  object_as :chart

  type :string
  def id = chart.id

  type :string
  def tool_call_id = chart.tool_call_id

  type :string
  def title = chart.title

  type :string
  def unit = chart.unit.to_s

  # The run step that drew it, for a chart from an investigation.
  type :number, optional: true
  def step_position = chart.step_position

  # The chart's page on the provider, where the full, live chart is.
  type :string, optional: true
  def source_url = chart.source_url

  type :string
  def range_start = chart.range_start.utc.iso8601

  type :string
  def range_end = chart.range_end.utc.iso8601

  # Each line with its [time, value] points, time as ISO 8601.
  type "{ label: string; points: [string, number][] }[]"
  def series = Array(chart.series)
end
