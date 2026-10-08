# Seen in real chats, once Halon had said it could not do something it kept saying so. Told "you do have access", it
# made the same wrong call and gave the same refusal, and asked to read an image again it said it still could not
# without checking anything. A result that says something cannot be used ends with AS_READ, and when a turn read one,
# the person's next message reaches Halon with a note that those results may be out of date.
module Chat::StaleRefusals
  AS_READ = "This is how it stood when read just now. After the person disputes it, says they changed something or " \
            "asks again, read it again rather than repeating it.".freeze
  SHOWN = 3
  LINE_LIMIT = 200

  module_function

  # The note for the turn the person's newest message starts, or nil when the turn before read no such result.
  def note(chat)
    asked = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).reorder(created_at: :desc, id: :desc).limit(2).to_a
    return if asked.size < 2

    newest, previous = asked
    refused = refusals_between(chat, previous.created_at, newest.created_at)
    return if refused.empty?

    lines = refused.first(SHOWN).map { |name, said| "- #{name}: #{said}" }
    "Before this message, your last answer rested on results that said something could not be used:\n#{lines.join("\n")}\n" \
      "They describe the moment they were read. If this message disputes that, says something changed or asks again, check " \
      "again in this turn before you answer, by opening the group again, looking for the tool by name in every group, or " \
      "reading the setting or permission again, and try another route if the first was wrong. Then say what you found now. " \
      "Never repeat the earlier answer without that check."
  end

  # Each call in the window whose result says something cannot be used, by its tool's name and the result's first line.
  def refusals_between(chat, from, to)
    asking = chat.messages.where(created_at: from..to).select(:id)
    calls = chat.tool_calls.where(message_id: asking).includes(:result).order(:created_at)
    calls.filter_map do |call|
      said = call.result&.content.to_s
      next unless said.include?(AS_READ)

      first = said.sub(AS_READ, "").lines.map(&:strip).reject { |line| line.empty? || line.start_with?("<") }.first
      [ call.name, first.to_s.truncate(LINE_LIMIT) ]
    end
  end
end
