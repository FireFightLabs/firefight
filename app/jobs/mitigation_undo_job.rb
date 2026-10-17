# Moves a temporary change whose undo a model used to write to being put back in the chat, for a job queued before.
class MitigationUndoJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(mitigation_id) { mitigation_id }, duration: 10.minutes

  def perform(mitigation_id)
    mitigation = Chat::Mitigation.find_by(id: mitigation_id)
    return unless mitigation&.undo_state == Chat::Mitigation::UNDO_WRITING

    # A model no longer writes an undo, so one still waiting for it is put back in the chat instead.
    mitigation.update!(undo_state: Chat::Mitigation::UNDO_IN_CHAT, undo_note: Chat::Mitigation::IN_CHAT_NOTE)
  end
end
