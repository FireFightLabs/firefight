# One check a review ran on a reported finding before writing it, on a chat of its own so it reads the code fresh. Kept
# names the finding it wrote or strengthened, dropped says why. Nobody sees a dropped finding, so this is where a review
# says what it let go and why. A check with no verdict stopped before it settled, and its finding was not written.
class PullRequestReview::Check < ApplicationRecord
  VERDICT_KEPT = "kept"
  VERDICT_DROPPED = "dropped"
  VERDICTS = [ VERDICT_KEPT, VERDICT_DROPPED ].freeze

  belongs_to :review, class_name: "PullRequestReview", foreign_key: :pull_request_review_id, inverse_of: :checks
  belongs_to :finding, class_name: "PullRequestReview::Finding", optional: true
  has_one :chat, as: :owner, dependent: :destroy

  validates :claim, presence: true
  validates :verdict, inclusion: { in: VERDICTS }, allow_nil: true

  delegate :workspace, :workspace_id, to: :review

  def kept? = verdict == VERDICT_KEPT

  def dropped? = verdict == VERDICT_DROPPED

  def settled!(verdict, reason:, finding: nil, spent_micros: 0)
    update!(verdict: verdict, reason: reason, finding: finding, spent_micros: spent_micros)
  end
end
