# Posts a review that finished high risk in the owning service's channel, apart from the review, so a channel that
# cannot take it never touches what the review posted on the pull request.
class PullRequestReviewAlertJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(review_id) { PullRequestReviewPostJob.pull_request_key(review_id) }, duration: 5.minutes

  retry_on PullRequestReviewAlertService::Retry, wait: :polynomially_longer, attempts: 5

  discard_on ActiveRecord::RecordNotFound

  def perform(review_id)
    PullRequestReviewAlertService.new(PullRequestReview.find(review_id)).post!
  end
end
