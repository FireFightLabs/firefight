# Everything a helper read, whole, so the chat or run that handed it the check opens it with read_result rather than
# reading it again. Each is named after its helper, such as helper_2_result_3, and is never saved a second time. A result
# the helper's own chat saved because it was large, or put away to make room, is read from where it was saved.
module Chat::Helper::Results
  extend ActiveSupport::Concern

  RESULT_INFIX = "_result_".freeze
  # What a helper's own chat holds that is no read of anything.
  NOT_READS = [ Chat::Helper::REPORT_FINDINGS, Chat::Helper::OPEN_TOOLS ].freeze

  class_methods do
    # Every helper's results in the chat that asked, or only those of the helper named, such as helper_2. A helper exists
    # only inside the chat that started it, so nothing outside that chat is ever read.
    def results_in(chat, helper: nil)
      handles = handles_in(chat.id)
      wanted = helper ? handles.select { |_id, handle| handle == helper } : handles
      where(id: wanted.keys).in_order.includes(:own_chat).flat_map { |each| each.results(wanted.fetch(each.id)) }
    end
  end

  # Unsaved Chat::SavedResult rows, so read_result pages and searches them as it does the chat's own.
  def results(handle = self.handle)
    return [] unless own_chat

    saved = own_chat.saved_results.index_by(&:handle)
    taken = Set.new
    read = read_messages.filter_map do |message|
      said = FirefightAi::Evidence.unframe(message.content)
      tool = message.ruby_llm_parent_tool_call&.name || said.tool
      next if NOT_READS.include?(tool)

      kept = saved[FirefightAi::Evidence.saved_handle(said.body) || said.body[Chat::Compacting::STUBBED_AS, :handle]]
      taken << kept.handle if kept
      [ tool || kept&.tool_name, kept ? kept.content : said.body, said.step || kept&.step ]
    end
    put_away = saved.values.reject { |one| taken.include?(one.handle) }.map { |one| [ one.tool_name, one.content, one.step ] }
    (read + put_away).each_with_index.map do |(tool, text, step), index|
      Chat::SavedResult.new(handle: "#{handle}#{RESULT_INFIX}#{index + 1}", tool_name: tool.to_s, content: text.to_s,
                            line_count: text.to_s.lines.size, step: step)
    end
  end

  # What it read, as the asking loop is told it when it ended without a report, each by the name read_result opens it
  # with. nil when it read nothing.
  def read_list
    listed = results.map { |one| "#{one.handle} (#{[ one.tool_name, ("step #{one.step}" if one.step), "#{one.line_count} lines" ].compact.join(', ')})" }
    "It read #{listed.join(', ')}." if listed.any?
  end

  private

  def read_messages
    Chat::Message.where(chat_id: own_chat.id, role: Chat::Message::ROLE_TOOL).includes(:ruby_llm_parent_tool_call).order(:created_at, :id)
  end
end
