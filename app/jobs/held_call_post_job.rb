# Asks for a call an approval rule held in the chat's thread, with Approve and Deny for its approvers.
class HeldCallPostJob < ApplicationJob
  queue_as :conversations

  def perform(held_call_id)
    held = Chat::HeldCall.find_by(id: held_call_id)
    Conversation::HeldCalls.held!(held) if held
  end
end
