# Checks whether a push fixed one open finding on its pull request, and says so on its thread (PullRequestReviewThreads).
class PullRequestReviewRecheckJob < ApplicationJob
  queue_as :webhooks

  limits_concurrency key: ->(finding_id, *) { finding_id }, duration: 10.minutes

  # Declared first, so the discards below are checked before it.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound
  discard_on FirefightAi::OutOfCredit

  def perform(finding_id, base, head)
    PullRequestReviewThreads.new(PullRequestReview::Finding.find(finding_id)).recheck!(base, head)
  end
end
