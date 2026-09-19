class ConversationReplyJob < ApplicationJob
  queue_as :investigations

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    say_nothing_came_of_it(job)
  end
  discard_on FirefightAi::TerminalError do |job, _error|
    say_nothing_came_of_it(job)
  end
  discard_on ActiveRecord::RecordNotFound

  # The person is told when the job gives up, or they would wait forever.
  def self.say_nothing_came_of_it(job)
    conversation = Conversation.find_by(id: job.arguments.first)
    return unless conversation

    conversation.note!(Conversation::Delivery::FAILED)
    Conversation::Delivery.for(conversation).failed!
  end

  # A job queued before the asker was passed along falls back to whoever started the conversation.
  def perform(conversation_id, asker_id = nil)
    conversation = Conversation.find(conversation_id)
    asker = conversation.workspace.workspace_memberships.find_by(id: asker_id) || conversation.started_by
    Conversation::Runner.new(conversation, asker: asker).run
  end
end
