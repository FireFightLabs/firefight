# A finding from a strict lesson on a pull request not merged yet, as the Lessons tab shows it: what it says, the pull
# request it holds, and who overrode it and why when someone did.
class HeldPullRequestFindingSerializer < BaseSerializer
  object_as :finding

  type :string
  def id = finding.id

  type :string
  def review_id = finding.pull_request_review_id

  type :string
  def repository = finding.review.repository

  type :number
  def number = finding.review.number

  type :string, optional: true
  def title = finding.review.title

  type :string, optional: true
  def url = finding.review.url

  type :string
  def claim = finding.claim

  type :string
  def lesson_label = finding.lesson_label

  type :string, optional: true
  def lesson_url = finding.lesson.lesson_origin_url

  type :boolean
  def lesson_elsewhere = finding.lesson.from_pull_request?

  type :string, optional: true
  def overridden_by = (finding.overridden_by&.display_name || ("Someone" if finding.overridden?))

  type :string, optional: true
  def overridden_at = finding.overridden_at&.utc&.iso8601

  type :string, optional: true
  def override_reason = finding.override_reason

  type :string, optional: true
  def override_blocked_reason = finding.override_blocked_reason
end
