# Runs the undo of a temporary change someone pressed Undo now on, already claimed as undoing.
class MitigationUndoRunJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(mitigation_id) { mitigation_id }, duration: 10.minutes
  # An undo a worker died in the middle of may have gone through, so the sweep ends it saying so rather than running it again.
  self.runs_again_when_interrupted = false

  def perform(mitigation_id)
    mitigation = Chat::Mitigation.find_by(id: mitigation_id)
    return unless mitigation&.status == Chat::Mitigation::STATUS_UNDOING

    Conversation::Mitigations.undo!(mitigation, by: mitigation.ended_by)
  end
end
