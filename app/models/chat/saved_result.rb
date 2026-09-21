# What a tool said, kept whole because it was too large to hand the model in one piece. The agent
# is shown how it starts and ends, and reads the rest by line or by search.
class Chat::SavedResult < ApplicationRecord
  self.table_name = "chat_saved_results"

  # A ceiling on storage, not on what the agent may read. Past it the rest is dropped and the record says so.
  MAX_KEPT = 5_000_000

  Match = Data.define(:line, :lines)

  belongs_to :chat

  # Tool output is the customer's data.
  encrypts :content

  validates :handle, :tool_name, presence: true

  scope :in_order, -> { order(:created_at, :handle) }

  # Called on a chat's own results, so the name counts within that chat. One worker holds a chat
  # at a time, and the unique index settles it if two ever meet.
  def self.keep!(tool_name:, text:)
    kept = text.to_s[0, MAX_KEPT]
    create!(handle: "result_#{count + 1}", tool_name: tool_name, content: kept, line_count: kept.lines.size)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def lines_between(from, to)
    first = [ from.to_i, 1 ].max
    last = [ to.to_i, line_count ].min
    return [] if first > last

    (first..last).map { |number| [ number, all_lines[number - 1] ] }
  end

  # Plain text, whatever its case. A pattern would let a result choose what a search costs.
  def matches(query, context:)
    wanted = query.to_s.downcase
    return [] if wanted.empty?

    all_lines.each_index.filter_map do |index|
      next unless all_lines[index].downcase.include?(wanted)

      Match.new(line: index + 1, lines: lines_between(index + 1 - context, index + 1 + context))
    end
  end

  private

  def all_lines = @all_lines ||= content.lines.map(&:chomp)
end
