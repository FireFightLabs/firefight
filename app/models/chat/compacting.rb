# How a chat makes room when the model's window fills. First the cheap way, moving old tool
# results into saved results and leaving a line that says where they went. Only when that is not
# enough are the old messages put away and the chat started again from what is already on record.
module Chat::Compacting
  extend ActiveSupport::Concern

  # The newest results stay whole, since the agent is still working from them.
  KEEP_RECENT = 5
  # Every clear makes the provider read the chat again uncached, so a small one is not worth it.
  MIN_FREED_SHARE = 0.05
  RECENT_IN_FULL = 2

  STUB = "[Shortened to save room. The full result is saved as %<handle>s. Read it again with read_result.]".freeze
  STUB_MARK = "[Shortened to save room.".freeze

  included do
    has_many :compactions, -> { order(:created_at) }, class_name: "Chat::Compaction", dependent: :destroy, inverse_of: :chat
  end

  # Tokens freed, by estimate. Zero when clearing was not worth doing.
  def clear_old_results!(tokens_before:)
    clearable = clearable_results(keep: KEEP_RECENT)
    freed = tokens_in(clearable)
    return 0 if clearable.empty? || freed < context_window! * MIN_FREED_SHARE

    transaction do
      clearable.each { |message| shorten!(message) }
      compactions.create!(stage: Chat::Compaction::STAGE_CLEARED, tokens_before: tokens_before, tokens_freed: freed, messages_affected: clearable.size)
    end
    freed
  end

  # The old messages stop being sent and stay in the database. What the person and the agent said
  # to each other is kept, since that is the conversation itself.
  def rebuild!(note:, tokens_before:)
    recent = sent_messages.where(role: Chat::Message::ROLE_TOOL).last(RECENT_IN_FULL).map(&:content)
    transaction do
      # Saved before they are put away, so every result stays readable by name.
      clearable_results(keep: 0).each { |message| shorten!(message) }
      put_away = working_messages + written_note(note)
      put_away.each { |message| message.update!(archived_at: Time.current) }
      nudge!(fresh_start(note, recent))
      compactions.create!(stage: Chat::Compaction::STAGE_REBUILT, tokens_before: tokens_before, messages_affected: put_away.size, note: note)
    end
    sent_messages.reset
  end

  private

  def clearable_results(keep:)
    results = sent_messages.where(role: Chat::Message::ROLE_TOOL).to_a
    (keep.zero? ? results : results[0...-keep] || []).reject { |message| message.content.to_s.include?(STUB_MARK) }
  end

  def tokens_in(messages) = messages.sum { |message| message.content.to_s.length } / Chat::CHARACTERS_PER_TOKEN

  def shorten!(message)
    said = FirefightAi::Evidence.unframe(message.content)
    handle = FirefightAi::Evidence.saved_handle(said.body) ||
             saved_results.keep!(tool_name: said.tool, text: said.body, step: said.step).handle
    message.update!(content: FirefightAi::Evidence.frame(said.tool, format(STUB, handle: handle), step: said.step))
  end

  # Everything but the instructions, and for a conversation everything but the two sides of it.
  def working_messages
    sent_messages.where.not(role: Chat::Message::ROLE_SYSTEM).includes(:ruby_llm_tool_calls).reject do |message|
      owner.keeps_in_memory?(message)
    end
  end

  # The note is the agent talking to itself, so it is marked like a nudge and never read back to a person.
  def written_note(note)
    return [] if note.blank?

    written = sent_messages.where(role: Chat::Message::ROLE_ASSISTANT).last
    return [] unless written&.content == note

    written.update!(nudge: true)
    [ written ]
  end

  def fresh_start(note, recent)
    [
      "Your earlier working messages were put away to make room. Nothing is lost. This is where things stand.",
      owner.memory_brief,
      saved_results_brief,
      ("Your own note from just before:\n#{note}" if note.present?),
      ("The last results you were working from:\n#{recent.join("\n")}" if recent.any?),
      "Carry on from here."
    ].compact_blank.join("\n\n")
  end

  def saved_results_brief
    saved = saved_results.to_a
    return nil if saved.empty?

    lines = saved.map do |one|
      "#{one.handle}: #{[ ("step #{one.step}" if one.step), one.tool_name, "#{one.line_count} lines" ].compact.join(', ')}"
    end
    "Every tool result so far is saved in full. Read any of them with read_result:\n#{lines.join("\n")}"
  end
end
