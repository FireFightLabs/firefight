# A review or one of its findings changed (PullRequestReview::Announcing), or an approved lesson behind its findings
# did (Chat::Memory::Lesson::EVENT), so the pull request's check is worked out again, and a review that finished high
# risk is posted in the owning service's channel. The models only say it happened, and listening is done here.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe(PullRequestReview::Announcing::EVENT) do |event|
    payload = event.payload
    next if payload[:change] == PullRequestReview::CHANGE_STARTED

    PullRequestReviewCommitStatusJob.perform_later(payload[:review_id])
    PullRequestReviewAlertJob.perform_later(payload[:review_id]) if payload[:change] == PullRequestReview::CHANGE_FINISHED
  end

  ActiveSupport::Notifications.subscribe(Chat::Memory::Lesson::EVENT) do |event|
    Array(event.payload[:review_ids]).each { |review_id| PullRequestReviewCommitStatusJob.perform_later(review_id) }
  end
end
