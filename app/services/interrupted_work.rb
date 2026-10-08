# What the recovery sweep does, in one place. Jobs the queue failed when their worker stopped run again, and work whose
# job will not run again, or was lost before it ran, is handed to a new job or ended with a plain reason. Every step is
# guarded on the row it changes, so a second sweep, or a job finishing late, changes nothing.
class InterruptedWork
  def self.recover!
    InterruptedJob.run_again!
    # A run nobody holds holds its subject's only slot. A second job for one run is harmless, the claim decides.
    Investigation.abandoned.find_each { |investigation| InvestigationJob.perform_later(investigation.id) }
    Conversation::HeldCalls.recover!
    Postmortem.generation_stalled.find_each { |postmortem| PostmortemGenerationJob.give_up_interrupted!(postmortem) }
    IssueSyncService.give_up_lost_openings!
    WebhookDelivery.give_up_interrupted!
    ResourceMap::ReceivedEvent.give_up_interrupted!
    JobRun.forget_old!
  end
end
