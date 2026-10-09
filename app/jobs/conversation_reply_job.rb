class ConversationReplyJob < ApplicationJob
  # Its own queue, so an answer someone is waiting for never sits behind an investigation.
  queue_as :conversations

  # A second turn would clear away the empty reply RubyLLM saves while the first is working, orphaning its tool results.
  # The lock outlives a dead worker no longer than the page waits on it.
  limits_concurrency key: ->(conversation_id, *) { conversation_id }, duration: Conversation::REPLY_CEILING

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    say_nothing_came_of_it(job)
  end
  discard_on FirefightAi::TerminalError do |job, _error|
    say_nothing_came_of_it(job)
  end
  # Declared after TerminalError, so it is the one that answers.
  discard_on FirefightAi::OutOfCredit do |job, _error|
    conversation = Conversation.find_by(id: job.arguments.first)
    Conversation::Delivery.give_up!(conversation, AiCredit.cannot(conversation.workspace)) if conversation
  end
  discard_on ActiveRecord::RecordNotFound
  # A turn that may have changed something is never run again, so Conversation::Recovery decides, not InterruptedJob.
  self.runs_again_when_interrupted = false

  # The person is told when the job gives up, or they would wait forever.
  def self.say_nothing_came_of_it(job)
    conversation = Conversation.find_by(id: job.arguments.first)
    Conversation::Delivery.give_up!(conversation, Conversation::Delivery::FAILED) if conversation
  end

  # A job queued before the asker was passed along falls back to whoever started the conversation. A held call someone
  # pressed Run on runs at the start of the turn, so it never lands in the middle of another. A watch step handed back
  # to Halon starts a turn of its own that only reads. Fix it pressed on a pull request Halon opened runs its code change
  # at the start of the turn too, and so does Continue on a code change paused at its spending limit.
  def perform(conversation_id, asker_id = nil, held_call_id = nil, watch_step_id = nil, pull_request_notice_id = nil, pause_id = nil)
    conversation = Conversation.find(conversation_id)
    asker = conversation.workspace.workspace_memberships.find_by(id: asker_id) || conversation.started_by
    held = conversation.chat&.held_calls&.find_by(id: held_call_id) if held_call_id
    handed_back = Chat::Watch::Step.joins(:watch).find_by(id: watch_step_id, chat_watches: { chat_id: conversation.chat&.id }) if watch_step_id
    fixing = CodeAgentSession::Notice.find_by(id: pull_request_notice_id, conversation_id: conversation.id) if pull_request_notice_id
    continuing = CodeAgentSession::Pause.find_by(id: pause_id, conversation_id: conversation.id) if pause_id
    Conversation::Runner.new(conversation, asker: asker, **{ held_call: held, handed_back: handed_back, pull_request_fix: fixing,
                                                             code_pause: continuing }.compact).run
    # The next question may read the same code, so the box waits a while before it is let go.
    CodeBoxIdleJob.set(wait: CodeBox::IDLE_AFTER).perform_later(conversation.code_box_key) if CodeBox.live.exists?(key: conversation.code_box_key)
  end
end
