# A reply job can die without a word: a worker killed by a deploy or a crash is failed by the queue and never retried, so
# the person would watch Halon work forever. The sweep finds a turn still owed whose job is gone. It runs the turn again
# once when nothing in it could have changed anything, and otherwise ends it saying so.
class Conversation::Recovery
  INTERRUPTED = "I was interrupted before I finished. Ask me again.".freeze
  # A question's job is queued a moment after the question is saved, so a turn owed for less than this is left alone.
  SETTLING = 1.minute

  # Past the ceiling the page has stopped waiting, so an old turn is not answered out of nowhere.
  def self.sweep!(jobs: Conversation::ReplyJobs)
    Conversation.where.not(kind: Conversation::KIND_MCP)
      .where(answer_owed_since: Conversation::REPLY_CEILING.ago..SETTLING.ago)
      .find_each { |conversation| recover(conversation, jobs: jobs) }
  end

  # An MCP chat is answered inside the request that asked, with no job to lose, so it is never swept. Each transition is
  # one guarded statement on the turn as it was read, so a turn started since, or one another sweep took, is never touched.
  def self.recover(conversation, jobs:)
    checked_at = Time.current
    return if jobs.waiting_or_running?(conversation)

    owed = conversation.answer_owed_since
    failed = jobs.last_failed(conversation, since: owed)
    if failed && conversation.reply_recovered_at.nil? && !changed_anything?(conversation, owed)
      jobs.retry!(failed) if conversation.rerun_lost_reply!(owed)
    elsif conversation.end_lost_reply!(owed)
      conversation.chat&.discard_interrupted_reply!(before: checked_at)
      conversation.chat&.close_unfinished_calls!(before: checked_at)
      conversation.note!(INTERRUPTED)
      delivery = Conversation::Delivery.for(conversation)
      delivery.cut_off!
      delivery.failed!(INTERRUPTED)
    end
  end

  # A call to anything that changes things may have done it before the worker died, so the turn is never run again.
  def self.changed_anything?(conversation, owed)
    chat = conversation.chat
    return false unless chat

    chat.tool_calls.where(created_at: owed..).pluck(:name, :arguments)
      .any? { |name, arguments| Chat::Tools.kind(name, conversation.workspace, arguments) == Chat::Tools::KIND_ACT }
  end
  private_class_method :changed_anything?
end
