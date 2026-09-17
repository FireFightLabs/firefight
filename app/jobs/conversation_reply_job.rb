class ConversationReplyJob < ApplicationJob
  queue_as :investigations

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    say_nothing_came_of_it(job)
  end
  discard_on FirefightAi::TerminalError do |job, _error|
    say_nothing_came_of_it(job)
  end
  discard_on ActiveRecord::RecordNotFound

  # Nobody is left to answer once the job is given up on, and a person watching a spinner deserves
  # to hear that.
  def self.say_nothing_came_of_it(job)
    conversation = Conversation.find_by(id: job.arguments.first)
    Conversation::Delivery.for(conversation).failed! if conversation
  end

  def perform(conversation_id, question)
    Conversation::Runner.new(Conversation.find(conversation_id)).run(question: question)
  end
end
