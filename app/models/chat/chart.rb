# A chart a tool returned, kept with the chat whose tool call made it. series holds each line's label and its
# [time, value] points, as Integrations::Telemetry writes them.
class Chat::Chart < ApplicationRecord
  # What a platform needs to post a chart. png is drawn by Chat::Chart::Image.
  Post = Data.define(:title, :summary, :link, :png)

  belongs_to :chat

  encrypts :series
  encrypts :summary
  serialize :series, coder: JSON

  validates :tool_call_id, :title, :range_start, :range_end, presence: true

  scope :in_order, -> { order(:created_at, :position) }
  # A call id is unique only within its message, so the charts of a turn's calls are the ones drawn since it started.
  scope :drawn_by, ->(tool_call_ids, since:) { where(tool_call_id: tool_call_ids, created_at: since..) }

  # A thread gets at most this many charts under one answer, the first ones the agent drew.
  POSTED_LIMIT = 6

  # What Halon names the chart by in its answer (Chat::Chart::Marker).
  def handle = id.to_s.first(8)

  def to_post = Post.new(title: title, summary: summary.to_s, link: source_url, png: Image.new(self).png)

  # The charts to post under an answer, and a line saying how many were left out, so a thread never quietly misses one.
  def self.posted_under_answer(charts)
    all = charts.to_a
    return if all.empty?

    posts = all.first(POSTED_LIMIT).map(&:to_post)
    left_out = all.size - POSTED_LIMIT
    if left_out.positive?
      posts << Post.new(title: "#{left_out} more #{'chart'.pluralize(left_out)}", summary: "Ask for a metric by name to see it here.", link: nil, png: nil)
    end
    yield posts
  end

  # Keeps the charts in one tool result. A chart that cannot be read is left out on its own, so a malformed one never
  # fails the tool call it came with or loses the charts beside it.
  # Several answers to one call (connection: all) each add theirs after the ones already kept. Returns the charts kept.
  # Calls of one step running together keep theirs in the order they were asked (CallOrder).
  def self.record!(chat, tool_call_id, charts, step_position: nil)
    CallOrder.after_earlier_calls do
      kept = chat.charts.where(tool_call_id: tool_call_id).count
      Array(charts).each.with_index(kept).filter_map { |chart, index| keep(chat, tool_call_id, chart, index, step_position) }
    end
  end

  def self.keep(chat, tool_call_id, chart, index, step_position)
    from = Time.zone.parse(chart["from"].to_s)
    to = Time.zone.parse(chart["to"].to_s)
    return if from.nil? || to.nil? || chart["title"].blank?

    chat.charts.create!(
      tool_call_id: tool_call_id, step_position: step_position, position: index, title: chart["title"].to_s.truncate(200), unit: chart["unit"].to_s.truncate(40),
      range_start: from, range_end: to, series: Array(chart["series"]), summary: chart["summary"].to_s.truncate(2_000),
      source_url: (chart["link"].to_s if chart["link"].to_s.start_with?("https://"))
    )
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    Rails.logger.warn({ event: "chat.chart_not_kept", chat_id: chat.id, error: error.message }.to_json)
    nil
  end
  private_class_method :keep
end
