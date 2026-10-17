# Every minute it reminds about each temporary change about to run out, and undoes each one that ran out and was not
# kept. Each is claimed with one guarded update, so two sweeps never remind or undo twice. An undo a worker died
# in the middle of is ended as failed after Chat::Mitigation::CLAIM_LAPSES, since it may or may not have gone through. A
# change Halon was asked to put back in the chat and has not is said to be due by hand, once.
class MitigationSweepJob < ApplicationJob
  queue_as :background

  def perform
    Chat::Mitigation.remind_due.find_each { |mitigation| Conversation::Mitigations.remind!(mitigation) }
    Chat::Mitigation.expiry_due.pluck(:id).each { |id| MitigationExpiryJob.perform_later(id) }
    Chat::Mitigation.undo_lapsed.find_each { |mitigation| Conversation::Mitigations.give_up!(mitigation) }
    Chat::Mitigation.undo_ask_lapsed.find_each { |mitigation| Conversation::Mitigations.ask_lapsed!(mitigation) }
  end
end
