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

  # A thread gets at most this many charts under one answer, the first ones the agent drew.
  POSTED_LIMIT = 6

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

  # Keeps the charts in one tool result. A chart that cannot be read is left out, so a malformed result never fails the
  # tool call it came with.
  def self.record!(chat, tool_call_id, charts, step_position: nil)
    Array(charts).each_with_index do |chart, index|
      from = Time.zone.parse(chart["from"].to_s)
      to = Time.zone.parse(chart["to"].to_s)
      next if from.nil? || to.nil? || chart["title"].blank?

      chat.charts.create!(
        tool_call_id: tool_call_id, step_position: step_position, position: index, title: chart["title"].to_s.truncate(200), unit: chart["unit"].to_s.truncate(40),
        range_start: from, range_end: to, series: Array(chart["series"]), summary: chart["summary"].to_s.truncate(2_000),
        source_url: (chart["link"].to_s if chart["link"].to_s.start_with?("https://"))
      )
    end
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    Rails.logger.warn({ event: "chat.chart_not_kept", chat_id: chat.id, error: error.message }.to_json)
  end
end
