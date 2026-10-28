# Says on a pull request why a review a person asked for could not start (PullRequestReviewRefusalPosting), off the
# signal's worker.
class PullRequestReviewRefusalPostJob < ApplicationJob
  queue_as :webhooks

  limits_concurrency key: ->(refusal_id, *) { "pull_request_review_refusal:#{refusal_id}" }, duration: 5.minutes

  # A comment that could not go up after every try is dropped, so it no longer counts as said. One that was sent once and
  # never confirmed may be up, so it stays said and is never sent again.
  retry_on PullRequestReviewRefusalPosting::Retry, wait: :polynomially_longer, attempts: 5 do |job, error|
    refusal_id, = job.arguments
    refusal = PullRequestReview::Refusal.find_by(id: refusal_id)
    why = "Gave up after #{job.executions} tries. #{error.message}"
    refusal&.attempted_at ? refusal.unconfirmed!(why) : refusal&.dropped!(why)
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(refusal_id, approval_id = nil)
    PullRequestReviewRefusalPosting.new(PullRequestReview::Refusal.find(refusal_id)).post!(approval_id: approval_id)
  end
end
