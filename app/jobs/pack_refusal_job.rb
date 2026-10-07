# Shows a change Halon was refused for want of a pack where the chat lives, outside the turn that was refused.
class PackRefusalJob < ApplicationJob
  queue_as :conversations

  def perform(pack_refusal_id)
    refusal = Chat::PackRefusal.find_by(id: pack_refusal_id)
    PackRequestService.refused!(refusal) if refusal
  end
end
