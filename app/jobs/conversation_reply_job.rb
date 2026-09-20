class ConversationReplyJob < ApplicationJob
  # A turn long enough to reach this was left behind by a dead worker, and the chat would otherwise stay blocked.
  TURN_CEILING = 30.minutes

  queue_as :investigations

  # One turn at a time per chat. RubyLLM saves an empty reply while it works, which a second turn would clear away as
  # wreckage from a crash, orphaning the first turn's tool results and leaving a history no model will read.
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
