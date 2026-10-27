# Reads a chat for lasting facts once it has gone quiet, or at once when it is archived (ChatLearningService). Every
# turn queues one for when the chat would be quiet, and a job that finds something said since it was queued, or an
# answer still being written, leaves the chat to the job the newer turn queued.
class ConversationLearningJob < ApplicationJob
  # How long a chat goes without a word before Halon reads it for lessons.
  QUIET_AFTER = 30.minutes

  queue_as :background

  limits_concurrency key: ->(conversation_id, *) { "conversation_learning:#{conversation_id}" }, duration: 10.minutes

  discard_on ActiveRecord::RecordNotFound

  # quiet_since is when the turn that queued it ended, nil when the chat was archived.
  def perform(conversation_id, quiet_since = nil)
    conversation = Conversation.find(conversation_id)
    return if conversation.answer_owed?
    return if quiet_since && conversation.chat&.readable_messages&.exists?(created_at: quiet_since..)

    ChatLearningService.new(conversation).learn!
  end
end
