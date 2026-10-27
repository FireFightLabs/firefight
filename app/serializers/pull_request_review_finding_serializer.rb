# One finding of a review in full, as its page shows it to a workspace member: the claim, why, how it fails, the evidence
# the viewer may see, the fix, where it stands and the replies Halon could not post on the pull request, each with why.
class PullRequestReviewFindingSerializer < BaseSerializer
  object_as :finding

  attributes(
    id: { type: :string },
    claim: { type: :string },
    why: { type: :string },
    status: { type: :string },
    serious: { type: :boolean }
  )

  type :string
  def category = finding.category_label

  type :string
  def severity = finding.severity_label

  type :string
  def effort = finding.effort_label

  type "string[]"
  def failure_chain = finding.failure_chain

  has_many :evidence, serializer: HalonPreventedEvidenceSerializer
  def evidence = finding.evidence_items.select { |item| PullRequestReview::Evidence.shown?(item, options[:reachable] || Set.new) }

  type :string, optional: true
  def suggested_fix = finding.suggested_fix.presence

  type :string, optional: true
  def path = finding.path

  type :number, optional: true
  def line = finding.line

  type :string, optional: true
  def fixed_in_sha = finding.fixed_in_sha

  type :string, optional: true
  def withdrawn_reason = finding.withdrawn_reason.presence

  type :string, optional: true
  def comment_url = finding.host_comment_url.presence

  type "{ body: string; reason: string; at: string }[]"
  def unposted_replies = Array(finding.unposted_replies).map { |reply| reply.slice("body", "reason", "at") }
end
