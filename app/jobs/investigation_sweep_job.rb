# Hands abandoned runs to a new worker. A killed worker's job is not always retried, and a run
# nobody works on holds its subject's only slot. A second job for one run is harmless, the claim decides.
class InvestigationSweepJob < ApplicationJob
  queue_as :investigations

  def perform
    Investigation.abandoned.find_each { |investigation| InvestigationJob.perform_later(investigation.id) }
  end
end
