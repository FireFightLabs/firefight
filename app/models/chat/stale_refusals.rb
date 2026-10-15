# Seen in real chats, once Halon had said it could not do something it kept saying so. Told "you do have access", it
# made the same wrong call and gave the same refusal, and asked to read an image again it said it still could not
# without checking anything. Later, it told a person a repository needed a paid plan six hours and two turns after the
# one call that said so. A result that says something cannot be used ends with AS_READ, and a connected system's error
# is one too. When the last few turns read one, the person's next message reaches Halon with what each said and how
# long ago, as results that may be out of date.
module Chat::StaleRefusals
  AS_READ = "This is how it stood when read just now. After the person disputes it, says they changed something or " \
            "asks again, read it again rather than repeating it.".freeze
  SHOWN = 3
  LINE_LIMIT = 200
  # How many of the person's turns before this message the note looks back over, since an answer restates what one
  # before it said.
  TURNS_BACK = 3

  module_function

  # The note for the turn the person's newest message starts, or nil when none of the turns before read such a result.
  def note(chat)
    asked = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).reorder(created_at: :desc, id: :desc).limit(TURNS_BACK + 1).to_a
    return if asked.size < 2

    refused = refusals_between(chat, asked.last.created_at, asked.first.created_at)
    return if refused.empty?

    lines = refused.last(SHOWN).reverse.map { |name, at, said| "- #{name}, read #{ago(at)}: #{said}" }
    "Before this message, your recent answers rested on results that said something could not be used or failed:\n#{lines.join("\n")}\n" \
      "They describe the moment they were read, and what they named may have changed since. Never repeat one as how things " \
      "stand now. If this message disputes that, says something changed or asks again, check again in this turn before you " \
      "answer, by opening the group again, looking for the tool by name in every group, reading the setting or permission " \
      "again or making the call again, and try another route if the first was wrong. Then answer from what you found now."
  end

  # Each call in the window whose result says something cannot be used, or a connected system's error, by its tool's
  # name, when it was read and the result's first line. Firefight's own refusals, such as a plan's step that already
  # ended, say nothing of the outside world and are left out.
  def refusals_between(chat, from, to)
    asking = chat.messages.where(created_at: from..to).select(:id)
    calls = chat.tool_calls.where(message_id: asking).includes(:result).order(:created_at)
    calls.filter_map do |call|
      said = call.result&.content.to_s
      next unless said.include?(AS_READ) || provider_error?(chat.workspace, call)

      first = said.sub(AS_READ, "").lines.map(&:strip).reject { |line| line.empty? || line.start_with?("<") }.first
      [ call.name, call.created_at, first.to_s.truncate(LINE_LIMIT) ]
    end
  end

  def provider_error?(workspace, call)
    call.failed && call.failure_kind == Chat::StepOutcome::FAILURE_ERROR &&
      (workspace.tool_labels.key?(call.name) || Integrations::Capabilities.tool_names.include?(call.name))
  end

  def ago(at)
    minutes = ((Time.current - at) / 1.minute).round
    return "just now" if minutes < 1
    return "#{minutes} #{'minute'.pluralize(minutes)} ago" if minutes < 120

    hours = (minutes / 60.0).round
    return "#{hours} hours ago" if hours < 48

    "#{(hours / 24.0).round} days ago"
  end
end
