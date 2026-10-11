# What a chat's turn checks before a reply ends it (FirefightAi::AgentLoop checks:), each sending the turn back to Halon
# at most once. Both act only on a turn that touched the theory board, so a plain question never meets them.
# - The board: the leading cause is not confirmed while another is still open, so Halon tests what is open, in parallel
#   with helpers, or says plainly what is still open.
# - The challenger: a cause the turn confirmed is given to a separate quick call that looks only for evidence against
#   it (FirefightAi::Challenger), and anything it finds goes back to Halon with the reads that would settle it.
class Conversation::Checks
  OPEN = "Your theory board names a cause while %<open>s %<is>s still open. Test what is open now, at once with run_helpers " \
         "(or ask_specialist when you hold it), then update the board, or say plainly in your answer what is still open and " \
         "what would settle it.".freeze
  CHALLENGED = "A second look at the cause you confirmed, %<cause>s, found this against it: %<reason>s%<checks>s Read what " \
               "settles it, update the board, then answer.".freeze
  # How much of what the turn read the challenger is shown, newest first, each read cut to its share.
  READS_SHOWN = 12
  READ_LIMIT = 1_500

  # since is when the turn began. choice is the quick model the challenger runs on, facts what Firefight told the turn
  # before it began, and inferable and member what its call is ledgered under.
  def initialize(chat, since:, choice:, inferable:, member: nil, facts: nil)
    @chat = chat
    @since = since
    @choice = choice
    @inferable = inferable
    @member = member
    @facts = facts
  end

  def all = [ method(:open_board), method(:challenge) ]

  def open_board(_message)
    theories = touched or return nil
    leading = Chat::Theory.leading_of(theories)
    open = theories.select(&:open?) - [ leading ]
    return nil if leading.confirmed? && open.empty?
    return nil if theories.none?(&:confirmed?) && open.empty?

    still = (leading.open? ? [ leading ] : []) + open
    format(OPEN, open: still.map(&:title).to_sentence, is: still.one? ? "is" : "are")
  end

  def challenge(_message)
    theories = touched or return nil
    cause = theories.select(&:confirmed?).find { |theory| theory.status_changed_at >= @since }
    return nil unless cause

    verdict = FirefightAi::Challenger.new(@chat.workspace, inferable: @inferable, choice: @choice, member: @member)
                                     .challenge(cause: "#{cause.title}\nEvidence given: #{cause.evidence}", reads: reads, facts: @facts)
    return nil if verdict.holds?

    checks = verdict.checks.any? ? " To settle it: #{verdict.checks.join(' ')}" : ""
    format(CHALLENGED, cause: cause.title, reason: verdict.reason.presence || "a read that speaks against it.", checks: checks)
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "challenger.failed", chat_id: @chat.id, error: error.class.name }.to_json)
    nil
  end

  private

  # The board when this turn updated it, else nil.
  def touched
    theories = @chat.theories.reload.to_a
    theories if theories.any? { |theory| theory.updated_at >= @since }
  end

  def reads
    calls = RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name,
                                                  message_id: @chat.messages.where(created_at: @since..).select(:id))
                                           .where.not(result_id: nil).where.not(name: Chat::Tools::Theories::NAME)
                                           .includes(:result).order(created_at: :desc).limit(READS_SHOWN).to_a.reverse
    calls.map { |call| "#{call.name} #{call.arguments.to_json}:\n#{call.result.content.to_s.truncate(READ_LIMIT)}" }.join("\n\n")
  end
end
