# How the agent reads a tool result that was too large to be handed over whole. It reads a range
# of lines or searches, and with no result named it searches everything saved in the chat, which
# is how two logs are lined up on the same request or the same minute.
class Chat::Tools::ReadResult < RubyLLM::Tool
  PAGE_LINES = 400
  MATCH_LIMIT = 40
  CONTEXT_LINES = 2
  # Several results read together are not one tool's words.
  ALL_RESULTS = "saved_results".freeze

  description "Read more of a tool result that was saved because it was too large to show whole. " \
              "Give from_line and to_line to read a range, or search to find lines containing some text. " \
              "Leave result out to search every saved result at once, for example for a request id or a timestamp."
  parameter :result, description: "The saved result's name, such as result_1. Leave out to search all of them", required: false
  parameter :search, description: "Text to look for, whatever its case", required: false
  parameter :from_line, type: :integer, description: "First line to read", required: false
  parameter :to_line, type: :integer, description: "Last line to read", required: false

  def self.tool_name = "read_result"

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def execute(result: nil, search: nil, from_line: nil, to_line: nil)
    saved = @agent_run.chat&.saved_results.to_a
    return "Nothing has been saved in this chat yet." if saved.blank?

    chosen = result.present? ? saved.select { |one| one.handle == result.to_s.strip } : saved
    return unknown(result, saved) if chosen.empty?
    return searched(chosen, search) if search.present?
    return "Name one result to read lines from. Saved here: #{names(saved)}." unless chosen.one?

    page(chosen.sole, from_line, to_line)
  end

  private

  def unknown(result, saved) = "Nothing is saved as #{result}. Saved here: #{names(saved)}."

  def names(saved) = saved.map { |one| "#{one.handle} (#{one.tool_name}, #{one.line_count} lines)" }.join(", ")

  def page(saved, from_line, to_line)
    first = [ from_line.to_i, 1 ].max
    last = to_line.to_i.positive? ? to_line.to_i : first + PAGE_LINES - 1
    rows = within_limit(saved.lines_between(first, [ last, first + PAGE_LINES - 1 ].min))
    return "#{saved.handle} has #{saved.line_count} lines, so there is nothing at line #{first}." if rows.empty?

    reached = rows.last.first
    text = numbered(rows)
    text += "\n[Stopped at line #{reached}. Carry on with from_line #{reached + 1}.]" if reached < [ last, saved.line_count ].min
    FirefightAi::Evidence.frame(saved.tool_name, text)
  end

  def searched(chosen, search)
    found = chosen.flat_map { |saved| saved.matches(search, context: CONTEXT_LINES).map { |match| [ saved, match ] } }
    return "No lines containing #{search.inspect} in #{chosen.map(&:handle).join(', ')}." if found.empty?

    text = found.first(MATCH_LIMIT).map { |saved, match| "#{saved.handle} line #{match.line}:\n#{numbered(match.lines)}" }.join("\n\n")
    text += "\n\n[#{found.size - MATCH_LIMIT} more matches. Search for something narrower.]" if found.size > MATCH_LIMIT
    FirefightAi::Evidence.frame(chosen.one? ? chosen.sole.tool_name : ALL_RESULTS, text)
  end

  # Whole lines up to what this chat's model is handed at once, and always at least one.
  def within_limit(rows)
    limit = @agent_run.chat.result_limit
    used = 0
    rows.take_while.with_index do |(_number, line), index|
      used += line.length
      index.zero? || used <= limit
    end
  end

  def numbered(rows) = rows.map { |number, line| format("%6d  %s", number, line) }.join("\n")
end
