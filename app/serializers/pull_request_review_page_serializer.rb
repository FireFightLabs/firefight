# A pull request review as its page shows it: the pull request, how the review went and what it judged.
class PullRequestReviewPageSerializer < BaseSerializer
  object_as :review

  attributes(
    id: { type: :string },
    repository: { type: :string },
    number: { type: :number },
    status: { type: :string },
    head_sha: { type: :string }
  )

  type :string, optional: true
  def title = review.title.presence

  type :string, optional: true
  def url = review.url.presence

  type :string, optional: true
  def risk = review.risk&.capitalize

  type :string, optional: true
  def risk_reason = review.risk_reason.presence

  type :string, optional: true
  def summary = review.summary.presence

  type :string, optional: true
  def error_summary = review.error_summary.presence

  type :string, optional: true
  def finished_at = review.finished_at&.utc&.iso8601
end
