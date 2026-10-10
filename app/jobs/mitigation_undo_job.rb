# Writes how to undo a temporary change once it ran, away from the turn, since it asks a model.
class MitigationUndoJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(mitigation_id) { mitigation_id }, duration: 10.minutes

  def perform(mitigation_id)
    mitigation = Chat::Mitigation.find_by(id: mitigation_id)
    return unless mitigation&.undo_state == Chat::Mitigation::UNDO_WRITING

    Conversation::Mitigations.write_undo!(mitigation)
  end
end
