# Both entry points ask through here, so saving the question and queueing the reply live in one place.
class Conversation::Asking
  # The chat is created with its first question, so there is never an empty one.
  def self.start_personal(workspace:, member:, question:)
    conversation = Conversation.transaction do
      Conversation.start_personal!(workspace: workspace, member: member).tap { |started| started.ask!(question) }
    end
    reply(conversation, member)
  end

  # The asker is who the turn acts as, which in a Slack thread can be someone other than whoever started it.
  def self.ask(conversation, question, asker:)
    conversation.ask!(question)
    reply(conversation, asker)
  end

  def self.reply(conversation, asker)
    ConversationReplyJob.perform_later(conversation.id, asker&.id)
    conversation
  end
  private_class_method :reply
end
