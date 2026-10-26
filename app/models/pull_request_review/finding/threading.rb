# What a finding keeps of its thread on the pull request: its line comment, the comment of its own a serious finding gets,
# the replies Halon answered and the push it last checked a fix against. Each is taken in one guarded update, so a reply
# delivered twice or two pushes checked at once never say anything twice.
module PullRequestReview::Finding::Threading
  extend ActiveSupport::Concern

  # Kept without announcing, since posting the comment changed nothing a person reads of the finding.
  def posted_on_line!(reference) = update_columns(host_comment_id: reference, updated_at: Time.current)

  def serious_posted!(reference)
    self.class.where(id: id, serious_comment_id: nil).update_all(serious_comment_id: reference, updated_at: Time.current).positive?.tap { |won| reload if won }
  end

  # Takes one reply to answer. False when it was answered already.
  def claim_answer!(comment)
    self.class.where(id: id).where.not("answered_comment_ids ? :comment", comment: comment.to_s)
        .update_all([ "answered_comment_ids = answered_comment_ids || ?::jsonb, updated_at = ?", [ comment.to_s ].to_json, Time.current ]).positive?
  end

  # Takes the check of one push. False when that push was checked already.
  def claim_recheck!(sha)
    self.class.where(id: id, status: PullRequestReview::Finding::STATUS_OPEN).where("rechecked_sha IS DISTINCT FROM ?", sha)
        .update_all(rechecked_sha: sha, updated_at: Time.current).positive?
  end

  # The finding as Halon posted it, for the model that checks a fix or answers a reply.
  def as_posted = PullRequestReview::Comments.finding(self).sub(format(PullRequestReview::Comments::FINDING_MARK, id: id), "").strip
end
