# Sets a review's check once its findings or a lesson behind them changed. Runs apart from the review, so a code host
# that is slow or down never holds the review up.
class PullRequestReviewCommitStatusJob < ApplicationJob
  queue_as :default
  # One at a time per pull request, so the host is told states in the order they were worked out.
  limits_concurrency key: ->(review_id) { PullRequestReviewPostJob.pull_request_key(review_id) }, duration: 5.minutes

  discard_on ActiveRecord::RecordNotFound

  def perform(review_id)
    PullRequestReviewCommitStatusService.new(PullRequestReview.find(review_id)).update!
  end
end
