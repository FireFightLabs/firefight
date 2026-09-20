class ConversationReplyJob < ApplicationJob
  # A turn still holding the lock this long belongs to a dead worker, and the chat would wait forever on it.
  TURN_CEILING = 30.minutes

  queue_as :investigations

  # A second turn would clear away the empty reply RubyLLM saves while the first is working, orphaning its tool results.
  limits_concurrency key: ->(conversation_id, _asker_id = nil) { conversation_id }, duration: TURN_CEILING

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
