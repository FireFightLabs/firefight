# Puts what changed in a review on its pull request, off the worker that wrote it. One pull request's posts run one at a
# time, so the summary comment is posted once and every edit lands in order.
class PullRequestReviewPostJob < ApplicationJob
  queue_as :webhooks

  limits_concurrency key: ->(review_id, *) { PullRequestReviewPostJob.pull_request_key(review_id) }, duration: 10.minutes

  retry_on PullRequestReviewPosting::NotPosted, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def self.pull_request_key(review_id)
    review = PullRequestReview.find_by(id: review_id)
    review ? "pull_request_review:#{review.workspace_id}:#{review.repository.downcase}:#{review.number}" : "pull_request_review:#{review_id}"
  end

  def perform(review_id, finding_id, change, approval_id = nil)
    review = PullRequestReview.find(review_id)
    finding = review.findings.find_by(id: finding_id) if finding_id
    PullRequestReviewPosting.new(review).run!(change, finding: finding, approval_id: approval_id)
  end
end
