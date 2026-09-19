# Both entry points ask through here, so saving the question and queueing the reply live in one place.
class Conversation::Asking
  # The chat is created with its first question, so there is never an empty one.
  def self.start_personal(workspace:, member:, question:)
    conversation = Conversation.transaction do
      Conversation.start_personal!(workspace: workspace, member: member).tap { |started| started.ask!(question) }
    end
    reply(conversation)
  end

  def self.ask(conversation, question)
    conversation.ask!(question)
    reply(conversation)
  end

  def self.reply(conversation)
    ConversationReplyJob.perform_later(conversation.id)
    conversation
  end
  private_class_method :reply
end
