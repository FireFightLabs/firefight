class ConversationReplyJob < ApplicationJob
  # Its own queue, so an answer someone is waiting for never sits behind an investigation.
  queue_as :conversations

  # A second turn would clear away the empty reply RubyLLM saves while the first is working, orphaning its tool results.
  # The lock outlives a dead worker no longer than the page waits on it.
  limits_concurrency key: ->(conversation_id, _asker_id = nil) { conversation_id }, duration: Conversation::REPLY_CEILING

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
    conversation.reply_delivered!
    Conversation::Delivery.for(conversation).failed!
  end

  # A job queued before the asker was passed along falls back to whoever started the conversation.
  def perform(conversation_id, asker_id = nil)
    conversation = Conversation.find(conversation_id)
    asker = conversation.workspace.workspace_memberships.find_by(id: asker_id) || conversation.started_by
    Conversation::Runner.new(conversation, asker: asker).run
    # The next question may read the same code, so the box waits a while before it is let go.
    CodeBoxIdleJob.set(wait: CodeBox::IDLE_AFTER).perform_later(conversation.code_box_key) if CodeBox.live.exists?(key: conversation.code_box_key)
  end
end
