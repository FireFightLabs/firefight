# Both entry points ask through here, so saving the question and queueing the reply live in one place.
class Conversation::Asking
  # The chat is created with its first question, so there is never an empty one.
  def self.start_personal(workspace:, member:, question:, files: [], model: nil, subject: nil)
    conversation = Conversation.transaction do
      Conversation.start_personal!(workspace: workspace, member: member, model: model, subject: subject).tap { |started| started.ask!(question, files: files) }
    end
    reply(conversation, member)
  end

  # The asker is who the turn acts as, which in a Slack thread can be someone other than whoever started it.
  # A question sent while a turn runs joins that turn. The job queued behind it answers only what is left.
  # A question written in the chat platform is asked as the model reads it, and kept as written for the pages.
  # acknowledged_message_id is the message the platform marked as being worked on, marked done once it is answered.
  def self.ask(conversation, question, asker:, files: [], context: nil, as_written: nil, acknowledged_message_id: nil)
    conversation.ask!(question, asker: asker, files: files, context: context, as_written: as_written)
    conversation.acknowledged!(acknowledged_message_id)
    reply(conversation, asker)
  end

  def self.reply(conversation, asker)
    ConversationReplyJob.perform_later(conversation.id, asker&.id)
    conversation
  end
  private_class_method :reply
end
