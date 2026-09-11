class InvestigationJob < ApplicationJob
  queue_as :investigations

  discard_on ActiveRecord::RecordNotFound

  def perform(investigation_id)
    investigation = Investigation.find(investigation_id)
    # The loser of the claim leaves the run alone, so a retry after a crash resumes
    # rather than starting a second pass.
    return unless investigation.claim_running!

    # The seed pack, the planner, the branches and the Finding land in PR 2 to PR 5.
    # Until then a claimed run has nothing to do and closes itself instead of sitting
    # in running and blocking the next request for this incident.
    investigation.finish!(status: Investigation::STATUS_SUCCEEDED)
  rescue StandardError => error
    investigation&.finish!(status: Investigation::STATUS_FAILED, error_summary: error.class.name)
    raise
  end
end
