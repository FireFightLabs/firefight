# Says on a pull request why a review a person asked for there could not start, in one plain sentence
# (PullRequestReview::Comments.refused) and nothing else, since anyone may read a public repository. Only for a person's
# request, as often as PullRequestReview::Refusal says, and only through a connection that can post a review. The
# comment is the connection's own tool, made as Halon's review agent through the gateway, so a grant, a switched off
# tool, an approval rule and the activity log treat it like any other review post.
class PullRequestReviewRefusalPosting
  # Raised so the job tries again later, for a host that limited the rate, timed out, could not be reached or failed on
  # its side, or a conversation that could not be read back.
  class Retry < StandardError; end

  # A comment's time on the host and here may differ a little, so the read back starts this much before the first try.
  READ_BACK_SLACK = 1.minute

  # A refusal of a review a person asked for, said once on its pull request.
  def self.refused!(environment_row, signal, reason:)
    return unless PullRequestReview::Comments.refused(reason) && Integrations::PullRequestReviews.hosts?(environment_row.integration)

    refusal = PullRequestReview::Refusal.claim!(environment_row, signal, reason: reason)
    PullRequestReviewRefusalPostJob.perform_later(refusal.id) if refusal
  end

  # The approval a held comment waited on was decided. Approved, the job makes that call. Declined, nothing is said, and
  # the refusal no longer counts as said.
  def self.decided(approval, payload)
    refusal = PullRequestReview::Refusal.find_by(id: payload["refusal_id"], workspace_id: approval.workspace_id)
    return unless refusal

    if approval.approved?
      PullRequestReviewRefusalPostJob.perform_later(refusal.id, approval.id)
    else
      refusal.dropped!("The approval was declined.")
      Rails.logger.info({ event: "pull_request_review.refusal_declined", pull_request_review_refusal_id: refusal.id, approval_id: approval.id }.to_json)
    end
  end

  def initialize(refusal)
    @refusal = refusal
  end

  # Posts the comment, unless a review of the pull request started since, which makes it untrue. A comment tried before
  # may have gone up although the host never answered, so the conversation is read first and a comment found there is
  # kept rather than posted twice. A read that fails is tried again rather than risk a second comment.
  def post!(approval_id: nil)
    return unless @refusal.live?

    row = @refusal.integration_environment
    return @refusal.dropped!("The connection is gone or cannot post a review.") if row.nil? || !Integrations::PullRequestReviews.hosts?(row.integration)
    return @refusal.dropped!("A review of the pull request started since.") if @refusal.superseded?
    return if @refusal.attempted_at && found_posted!(row)

    @refusal.attempted!
    posted = Integrations::PullRequestReviews.call!(row, Integrations::PullRequestReviews::COMMENT, authorize: authorizer(approval_id), repository: @refusal.repository,
                                                                                                   number: @refusal.number, body: sentence)
    @refusal.posted!(posted)
  rescue AbilityGateway::PendingApproval => pending
    pending.approval.update!(resume_payload: { kind: PullRequestReview::Refusal::RESUME_KIND, refusal_id: @refusal.id })
    @refusal.held!(pending.approval)
  rescue Integrations::Error, AbilityGateway::Denied => error
    Rails.logger.warn({ event: "pull_request_review.refusal_not_posted", pull_request_review_refusal_id: @refusal.id, error: error.class.name,
                        message: error.message.truncate(300) }.to_json)
    raise Retry, error.message if Integrations::ReviewHost.retryable?(error)

    @refusal.dropped!(error.message)
  end

  private

  def sentence = PullRequestReview::Comments.refused(@refusal.reason)

  # The comment an earlier try posted, found in the conversation by its words and, where the host says who Firefight is,
  # its author. Kept as posted when found.
  def found_posted!(row)
    comments = Integrations::PullRequestReviews.call!(row, Integrations::PullRequestReviews::CONVERSATION, authorize: authorizer(nil), repository: @refusal.repository,
                                                                                                          number: @refusal.number, since: @refusal.attempted_at - READ_BACK_SLACK)
    raise Retry, "The conversation of PR ##{@refusal.number} in #{@refusal.repository} could not be read back." if comments.nil?

    identity = Integrations::PullRequestReviews.identity(row)
    found = comments.find do |comment|
      comment.body.strip == sentence && (identity.handles.empty? && identity.ids.empty? || identity.named?(comment.authors))
    end
    found && @refusal.posted!(found.reference)
  rescue Integrations::Error, AbilityGateway::Denied, AbilityGateway::PendingApproval => error
    raise Retry, "The conversation could not be read back. #{error.message}"
  end

  def authorizer(approval_id)
    refusal = @refusal
    ->(tool, arguments, &run) { refusal.authorize_post!(tool, arguments, approval_id: approval_id, &run) }
  end
end
