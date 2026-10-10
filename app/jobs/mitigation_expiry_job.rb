# Undoes one temporary change whose time ran out, as whoever asked for it, unless someone kept it first.
class MitigationExpiryJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(mitigation_id) { mitigation_id }, duration: 10.minutes
  # An undo a worker died in the middle of may have gone through, so the sweep ends it saying so rather than running it again.
  self.runs_again_when_interrupted = false

  def perform(mitigation_id)
    mitigation = Chat::Mitigation.find_by(id: mitigation_id)
    Conversation::Mitigations.expire!(mitigation) if mitigation
  end
end
