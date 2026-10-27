# A review says it changed (PullRequestReview::Announcing) and never names who posts it, so the posting listens here.
# Resolved on each event, so a reloaded class in development is the one called.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe(PullRequestReview::Announcing::EVENT) do |event|
    PullRequestReviewPosting.changed!(**event.payload.slice(:review_id, :finding_id, :change))
  end
end
