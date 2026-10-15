# What each of Halon's messages in a turn is to the person reading. Only a question put to them and the last words of
# the turn are said as messages. Words Halon wrote and then carried on working past, in the same turn, are a status
# line among its steps. A turn runs until the person's next message, and Halon's notes to itself never end one.
class Chat::TurnText
  # Words whose calls were put to the person to approve, which stay where they were asked whatever happened next.
  QUESTION = "question".freeze
  STATUS = "status".freeze
  RESULT = "result".freeze
  ROLES = [ QUESTION, STATUS, RESULT ].freeze

  # Message id to role, for each of Halon's messages with words. The messages may be one stretch of a chat or several,
  # and whatever comes after the newest of a chat's is read from the chat, up to the person's next message.
  def self.roles(messages)
    messages.group_by(&:chat_id).values.each_with_object({}) do |shown, roles|
      ordered = shown.sort_by { |message| [ message.created_at, message.id ] }
      carried_on = carried_on_after?(ordered.last)
      ordered.reverse_each do |message|
        if person?(message)
          carried_on = false
          next
        end
        next unless message.role == Chat::Message::ROLE_ASSISTANT

        calls = message.ruby_llm_tool_calls.to_a
        roles[message.id] = role_of(calls, carried_on) if message.content.present?
        carried_on ||= calls.any? || message.content.present?
      end
    end
  end

  def self.role_of(calls, carried_on)
    return QUESTION if calls.any? { |call| call.approval.present? }

    calls.any? || carried_on ? STATUS : RESULT
  end

  def self.person?(message) = message.role == Chat::Message::ROLE_USER && !message.nudge

  # Whether Halon wrote or called anything after this message before the person spoke again, read in one query of the
  # rest of the turn. The words are encrypted, so whether there are any is read here rather than queried.
  def self.carried_on_after?(message)
    return false if person?(message)

    messages = Chat::Message.arel_table
    after = message.chat.messages.unscope(:order).where(messages[:created_at].gt(message.created_at))
    spoke = after.where(role: Chat::Message::ROLE_USER, nudge: false).select(messages[:created_at].minimum)
    until_spoke = Arel::Nodes::NamedFunction.new("COALESCE", [ spoke.arel, Arel::Nodes.build_quoted("infinity") ])
    calls = RubyLLM::ActiveRecord::ToolCall.arel_table
    called = calls.project(Arel.star).where(calls[:message_id].eq(messages[:id])).exists.as("called")
    later = after.where(role: Chat::Message::ROLE_ASSISTANT).where(messages[:created_at].lt(until_spoke))
    later.select(:id, :content, called).any? { |written| written.called || written.content.present? }
  end
end
