# Says on a pull request why a review a person asked for there could not start, in one plain sentence
# (PullRequestReview::Comments.refused) and nothing else, since anyone may read a public repository. Only for a person's
# request, once per request (PullRequestReview::Refusal), and only through a connection that can post a review. The
# comment is the connection's own tool, made as Halon's review agent through the gateway, so a grant, a switched off
# tool, an approval rule and the activity log treat it like any other review post.
class PullRequestReviewRefusalPosting
  # Raised so the job tries again later, for a host that limited the rate, timed out or failed on its side.
  class Retry < StandardError; end

  # A refusal of a review a person asked for, said once on its pull request.
  def self.refused!(environment_row, signal, reason:)
    return unless PullRequestReview::Comments.refused(reason) && Integrations::PullRequestReviews.hosts?(environment_row.integration)

    refusal = PullRequestReview::Refusal.claim!(environment_row, signal, reason: reason)
    PullRequestReviewRefusalPostJob.perform_later(refusal.id) if refusal
  end

  # The approval a held comment waited on was decided. Approved, the job makes that call. Declined, nothing is said.
  def self.decided(approval, payload)
    refusal = PullRequestReview::Refusal.find_by(id: payload["refusal_id"], workspace_id: approval.workspace_id)
    return unless refusal

    if approval.approved?
      PullRequestReviewRefusalPostJob.perform_later(refusal.id, approval.id)
    else
      Rails.logger.info({ event: "pull_request_review.refusal_declined", pull_request_review_refusal_id: refusal.id, approval_id: approval.id }.to_json)
    end
  end

  def initialize(refusal)
    @refusal = refusal
  end

  def post!(approval_id: nil)
    row = @refusal.integration_environment
    return if @refusal.posted? || row.nil? || !Integrations::PullRequestReviews.hosts?(row.integration)

    posted = Integrations::PullRequestReviews.call!(row, Integrations::PullRequestReviews::COMMENT, authorize: authorizer(approval_id), repository: @refusal.repository,
                                                                                                   number: @refusal.number, body: PullRequestReview::Comments.refused(@refusal.reason))
    @refusal.posted!(posted)
  rescue AbilityGateway::PendingApproval => pending
    pending.approval.update!(resume_payload: { kind: PullRequestReview::Refusal::RESUME_KIND, refusal_id: @refusal.id })
  rescue Integrations::Error, AbilityGateway::Denied => error
    Rails.logger.warn({ event: "pull_request_review.refusal_not_posted", pull_request_review_refusal_id: @refusal.id, error: error.class.name,
                        message: error.message.truncate(300) }.to_json)
    raise Retry, error.message if Integrations::ReviewHost.retryable?(error)
  end

  private

  def authorizer(approval_id)
    refusal = @refusal
    ->(tool, arguments, &run) { refusal.authorize_post!(tool, arguments, approval_id: approval_id, &run) }
  end
end
