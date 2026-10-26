# Says a review or one of its findings changed, once the change commits, so whatever shows the review where people read
# it, such as the live comment on the pull request, catches up at once. The model only says it happened, as an EVENT
# notification with the review, the finding when there is one and what changed, and never names who listens. A
# finding announces itself on every commit, and a guarded update_all that skips callbacks calls announce! once it wins.
# A rehearsal is seen by nobody, so it is never announced.
module PullRequestReview::Announcing
  extend ActiveSupport::Concern

  EVENT = "changed.pull_request_review"

  CHANGE_STARTED = "started"
  CHANGE_FINISHED = "finished"
  CHANGE_FAILED = "failed"
  # A finding was verified and written.
  CHANGE_FINDING_ADDED = "finding_added"
  # A later check confirmed or strengthened a finding, or it was fixed.
  CHANGE_FINDING_CHANGED = "finding_changed"
  # A later check showed a finding was wrong.
  CHANGE_FINDING_WITHDRAWN = "finding_withdrawn"
  CHANGES = [ CHANGE_STARTED, CHANGE_FINISHED, CHANGE_FAILED, CHANGE_FINDING_ADDED, CHANGE_FINDING_CHANGED, CHANGE_FINDING_WITHDRAWN ].freeze

  # Waits for the outermost transaction, so a change that rolls back is never announced.
  def self.announce!(review, change, finding: nil)
    raise ArgumentError, "#{change} is not a review change" unless CHANGES.include?(change)
    return if review.rehearsal?

    payload = { review_id: review.id, finding_id: finding&.id, change: change }
    ActiveRecord.after_all_transactions_commit { ActiveSupport::Notifications.instrument(EVENT, payload) }
  end

  def announce!(change, finding: nil) = PullRequestReview::Announcing.announce!(self, change, finding: finding)
end
