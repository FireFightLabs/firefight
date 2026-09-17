class ConversationReplyJob < ApplicationJob
  queue_as :investigations

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    say_nothing_came_of_it(job)
  end
  discard_on FirefightAi::TerminalError do |job, _error|
    say_nothing_came_of_it(job)
  end
  discard_on ActiveRecord::RecordNotFound

  # Nobody answers once the job is given up on, so the person is told, in the chat as well as on
  # whatever they are watching.
  def self.say_nothing_came_of_it(job)
    conversation = Conversation.find_by(id: job.arguments.first)
    return unless conversation

    conversation.note!(Conversation::Delivery::FAILED)
    Conversation::Delivery.for(conversation).failed!
  end

  def perform(conversation_id)
    Conversation::Runner.new(Conversation.find(conversation_id)).run
  end
end
