class ConversationReplyJob < ApplicationJob
  queue_as :investigations

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, question)
    Conversation::Runner.new(Conversation.find(conversation_id)).run(question: question)
  end
end
