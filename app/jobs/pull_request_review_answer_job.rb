# Answers a person's reply on a thread Halon's review started (PullRequestReviewThreads).
class PullRequestReviewAnswerJob < ApplicationJob
  queue_as :webhooks

  limits_concurrency key: ->(finding_id, *) { finding_id }, duration: 10.minutes

  discard_on ActiveRecord::RecordNotFound
  discard_on FirefightAi::OutOfCredit

  def perform(finding_id, signal)
    PullRequestReviewThreads.new(PullRequestReview::Finding.find(finding_id)).answer!(Integrations::PullRequestReviews::Signal.new(**signal.symbolize_keys))
  end
end
