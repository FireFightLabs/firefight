# A person writing to Halon in their direct messages. Each message is a question in a chat of theirs, asked as them, and
# answered in the thread it was sent in. A new message carries on the chat they were having until it goes quiet for a
# day (Conversation::DIRECT_QUIET_AFTER), and a reply in a thread carries on that thread's chat. A reply under a message
# Halon sent on its own carries on their chat too, told what that message said and what it belongs to.
class Conversation::DirectMessages
  # thread_id is the thread the message was sent in, and its own id when it starts one. Returns a sentence to tell the
  # person when the message was not taken, or nil.
  def self.receive!(workspace:, sender:, channel_id:, message_id:, thread_id:, text:, files:, source:)
    new(workspace, sender, channel_id, thread_id, source).receive!(text, files, reply: thread_id != message_id)
  end

  def initialize(workspace, sender, channel_id, thread_id, source)
    @workspace = workspace
    @sender = sender
    @channel_id = channel_id
    @thread_id = thread_id
    @source = source
  end

  def receive!(text, files, reply:)
    # A run Halon answered in these direct messages takes a reply as a note while it works, as a mention in its thread.
    run = Investigation.live_in_thread(@workspace, @thread_id) if reply
    return run.add_note_from(text, member: @sender, source: @source, files: shared(files)) if run

    existing = Conversation.in_thread(@workspace, @channel_id, @thread_id)
    finished = Investigation.posted_in_thread(@workspace, @thread_id) if reply && !existing
    root = thread_root if reply && !existing && !finished
    started = root&.dig(:started)

    Conversation.ask_from_thread!(asker: @sender, workspace: @workspace, incident: existing&.incident || finished&.incident, source: @source) do
      conversation = existing || opened(finished, new_chat: finished.present? || started == PlatformAdapter::THREAD_STARTED_AS_CHAT)
      conversation.asked_in_thread!(@channel_id, @thread_id) if conversation.direct?
      Conversation::Asking.ask(conversation, text, asker: @sender, files: shared(files), context: replied_to(root))
    end
    nil
  rescue AbilityGateway::Denied => denied
    AuthorizedDispatch.denied_message(denied)
  end

  private

  # A thread of its own when the person opened a new chat or replied to a finished run, which it is then about.
  # Otherwise the chat they were having, held while it is looked up so two messages sent together share one.
  def opened(finished, new_chat:)
    return start_in_thread(finished&.incident) if new_chat

    @sender.with_lock { Conversation.direct_carrying_on(@sender) || start_in_thread(nil) }
  end

  def start_in_thread(subject)
    Conversation.start_direct!(workspace: @workspace, member: @sender, channel_id: @channel_id, thread_id: @thread_id, subject: subject)
  rescue ActiveRecord::RecordNotUnique
    Conversation.in_thread(@workspace, @channel_id, @thread_id) || raise
  end

  def thread_root = WorkspaceAdapter.for(@workspace).direct_thread_root(channel_id: @channel_id, thread_id: @thread_id)

  def replied_to(root)
    return nil unless root && root[:started] == PlatformAdapter::THREAD_STARTED_BY_APP

    Conversation::RepliedTo.context(@workspace, channel_id: @channel_id, message_id: @thread_id, text: root[:text])
  end

  def shared(files) = Conversation::SharedFiles.receive(workspace: @workspace, files: files, sender: @sender)
end
