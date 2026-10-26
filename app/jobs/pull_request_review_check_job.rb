# Sets a review's check once its findings or a lesson behind them changed. Runs apart from the review, so a code host
# that is slow or down never holds the review up.
class PullRequestReviewCheckJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(review_id)
    PullRequestReviewCheckService.new(PullRequestReview.find(review_id)).update!
  end
end
