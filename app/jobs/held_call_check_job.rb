# Halon reads how things stand now for a chat's call once it was approved, before the person who asked can run it.
class HeldCallCheckJob < ApplicationJob
  queue_as :conversations

  def perform(held_call_id)
    held = Chat::HeldCall.find_by(id: held_call_id)
    Conversation::HeldCalls.check!(held) if held
  end
end
