# Says on a pull request why a review a person asked for could not start (PullRequestReviewRefusalPosting), off the
# signal's worker.
class PullRequestReviewRefusalPostJob < ApplicationJob
  queue_as :webhooks

  limits_concurrency key: ->(refusal_id, *) { "pull_request_review_refusal:#{refusal_id}" }, duration: 5.minutes

  retry_on PullRequestReviewRefusalPosting::Retry, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(refusal_id, approval_id = nil)
    PullRequestReviewRefusalPosting.new(PullRequestReview::Refusal.find(refusal_id)).post!(approval_id: approval_id)
  end
end
