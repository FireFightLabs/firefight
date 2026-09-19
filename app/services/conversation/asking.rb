# Every way of asking the agent something ends here: the question is saved, then answered in the
# background. The dashboard and a Slack mention are only different ways in.
class Conversation::Asking
  # A dashboard chat exists only once something is asked in it, so there is never an empty one.
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
