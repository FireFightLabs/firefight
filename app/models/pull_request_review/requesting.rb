# How a review is asked for: a queued review of the pull request's head through the connection row that reads it, handed
# to a worker once it commits. It spends at most what the workspace lets one of Halon's runs spend. A pull request that
# is already under review answers the review that is running, so asking twice never runs two.
module PullRequestReview::Requesting
  extend ActiveSupport::Concern

  class_methods do
    def request!(connection_row, repository:, number:, head_sha:, trigger:, **attributes)
      workspace = connection_row.integration.workspace
      review = create!(workspace: workspace, integration_environment: connection_row, repository: repository, number: number, head_sha: head_sha,
                       trigger: trigger, max_spend_cents: workspace.investigation_limits.max_spend_cents, **attributes)
      ActiveRecord.after_all_transactions_commit { PullRequestReviewJob.perform_later(review.id) }
      review
    rescue ActiveRecord::RecordNotUnique
      workspace.pull_request_reviews.live.seen.of_pull_request(repository, number).first!
    end
  end
end
