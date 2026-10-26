# What a review keeps of what Halon posted on its pull request, so each thing is posted once and edited after. One
# summary comment serves every review of a pull request, carried from one push to the next, and a finding found again
# by a later review stays on the thread its first posting started.
module PullRequestReview::Posting
  extend ActiveSupport::Concern

  included do
    scope :of_same_pull_request, ->(review) { seen.where(workspace_id: review.workspace_id, repository: review.repository, number: review.number) }
  end

  class_methods do
    # The newest review of a pull request people see, which a push, a reply or a merge is about.
    def latest_of(workspace, repository, number)
      seen.where(workspace_id: workspace.id).where("lower(repository) = ?", repository.to_s.downcase).where(number: number)
          .order(:created_at).last
    end
  end

  # Every call that posts or reads for the review on the code host is made as Halon's review agent, which holds exactly
  # the tools a review posts and checks a fix through, never a person's reach. Approval rules still apply, and the
  # activity log names the pull request.
  def authorize_post!(tool, arguments, &)
    AbilityGateway.authorize!(
      principal: SystemAgent.pull_request_review, action_key: tool.action_key, workspace: workspace, scope: {}, params: arguments,
      context: { source: AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, triggered_by_label: "PR ##{number} in #{repository}" }, &
    )
  end

  # The summary comment this pull request already has, from this review or an earlier one.
  def summary_reference
    summary_comment_id.presence || self.class.of_same_pull_request(self).where.not(summary_comment_id: nil).order(:created_at).last&.summary_comment_id
  end

  # Kept once the summary comment is posted. False when another worker kept one first.
  def summary_posted!(reference)
    self.class.where(id: id, summary_comment_id: nil).update_all(summary_comment_id: reference, updated_at: Time.current).positive?.tap { |won| reload if won }
  end

  # Takes the posting of the review itself, once. False when it went out already or another worker took it.
  def claim_review_post!
    self.class.where(id: id, review_posted_at: nil).update_all(review_posted_at: Time.current, updated_at: Time.current).positive?
  end

  def review_posted!(reference) = update_columns(review_comment_id: reference, updated_at: Time.current)

  # Hands the posting back when nothing went up, so a retry takes it.
  def release_review_post! = self.class.where(id: id, review_comment_id: nil).update_all(review_posted_at: nil, updated_at: Time.current)

  # Every finding of this pull request as people should read it: one per problem, the thread a first posting started
  # standing for it, unless a later review found again what that thread says was fixed, which is new news.
  def pull_request_findings
    rows = PullRequestReview::Finding.where(pull_request_review_id: self.class.of_same_pull_request(self).select(:id))
                                     .includes(:review).order(:created_at).to_a
    rows.group_by(&:fingerprint).map do |_, same|
      thread = same.find { |finding| finding.host_comment_id.present? || finding.serious_comment_id.present? }
      newest = same.last
      thread && !(newest.open? && !thread.open?) ? thread : newest
    end
  end

  # A finding this review found that an earlier review of the pull request already posted and still holds open.
  def posted_before?(finding)
    PullRequestReview::Finding.where(pull_request_review_id: self.class.of_same_pull_request(self).where.not(id: id).select(:id))
                              .where(fingerprint: finding.fingerprint, status: PullRequestReview::Finding::STATUS_OPEN)
                              .where.not(host_comment_id: nil).exists?
  end

  # Findings of this pull request with a thread on a line, open, which a push may have fixed.
  def open_threads
    PullRequestReview::Finding.where(pull_request_review_id: self.class.of_same_pull_request(self).select(:id))
                              .still_open.where.not(host_comment_id: nil).includes(:review)
  end
end
