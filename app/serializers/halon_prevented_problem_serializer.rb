# A problem Halon's review caught and the author fixed before the pull request merged: the pull request, the claim, how
# it would have failed and the evidence for it, and where its comment sits on the code host.
class HalonPreventedProblemSerializer < BaseSerializer
  object_as :finding

  type :string
  def id = finding.id

  type :string
  def claim = finding.claim

  type :string
  def why = finding.why

  type :string
  def category = finding.category_label

  type :string
  def severity = finding.severity_label

  type :boolean
  def serious = finding.serious

  type "string[]"
  def failure_chain = finding.failure_chain

  has_many :evidence_items, as: :evidence, serializer: HalonPreventedEvidenceSerializer

  type :string, optional: true
  def path = finding.path

  type :number, optional: true
  def line = finding.line

  type :string, optional: true
  def fixed_in_sha = finding.fixed_in_sha

  type :string, optional: true
  def comment_url = finding.host_comment_url.presence

  type :string
  def repository = review.repository

  type :number
  def number = review.number

  type :string, optional: true
  def pull_request_title = review.title.presence

  type :string, optional: true
  def pull_request_url = review.url.presence

  type :string
  def merged_at = review.merged_at.utc.iso8601

  private

  def review = finding.review
end
