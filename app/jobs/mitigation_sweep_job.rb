# Every minute it reminds about each temporary change about to run out, and undoes each one that ran out and was not
# kept. Each is claimed with one guarded update, so two sweeps never remind or undo twice. An undo a worker died
# in the middle of is ended as failed after Chat::Mitigation::CLAIM_LAPSES, since it may or may not have gone through.
class MitigationSweepJob < ApplicationJob
  queue_as :background

  def perform
    Chat::Mitigation.remind_due.find_each { |mitigation| Conversation::Mitigations.remind!(mitigation) }
    Chat::Mitigation.expiry_due.pluck(:id).each { |id| MitigationExpiryJob.perform_later(id) }
    Chat::Mitigation.where(status: Chat::Mitigation::STATUS_UNDOING, claimed_at: ...Chat::Mitigation::CLAIM_LAPSES.ago)
                    .find_each { |mitigation| Conversation::Mitigations.give_up!(mitigation) }
  end
end
