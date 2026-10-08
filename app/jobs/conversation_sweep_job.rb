# Ends or runs again a reply whose worker died, so nobody waits on an answer that is not coming.
class ConversationSweepJob < ApplicationJob
  queue_as :conversations

  def perform
    Conversation::Recovery.sweep!
  end
end
