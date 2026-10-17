# Moves a temporary change whose undo a model used to write to being put back in the chat, for a job queued before.
class MitigationUndoJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(mitigation_id) { mitigation_id }, duration: 10.minutes

  def perform(mitigation_id)
    moved = Chat::Mitigation.where(id: mitigation_id, undo_state: Chat::Mitigation::UNDO_WRITING)
                            .update_all(undo_state: Chat::Mitigation::UNDO_IN_CHAT, undo_note: Chat::Mitigation::IN_CHAT_NOTE, updated_at: Time.current)
    return unless moved == 1

    Conversation::LiveDelivery.safeguard_moved(Chat::Mitigation.find(mitigation_id).conversation)
  end
end
