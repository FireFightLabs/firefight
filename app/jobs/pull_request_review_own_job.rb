# Halon reviews a pull request it opened once it is open, the same review anyone else's gets, since its own check before
# opening missed problems a review on the pull request caught.
class PullRequestReviewOwnJob < ApplicationJob
  queue_as :events

  discard_on ActiveRecord::RecordNotFound

  def perform(session_id)
    session = CodeAgentSession.find(session_id)
    row = session.integration_environment
    return unless row && session.pull_request_number && Integrations::PullRequestReviews.hosts?(row.integration)

    PullRequestReviewSignals.opened_by_halon!(row, repository: session.repository, number: session.pull_request_number)
  end
end
