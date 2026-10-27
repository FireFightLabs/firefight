# What a finding keeps of its thread on the pull request: its line comment and the page it opens at, the comment of its
# own a serious finding gets, what was said on the thread, the replies Halon could not post anywhere, the replies Halon
# answered and the push it last checked a fix against. Each is taken in one guarded update, so a reply delivered twice or
# two pushes checked at once never say anything twice.
module PullRequestReview::Finding::Threading
  extend ActiveSupport::Concern

  # The thread's history a reply is answered with is cut to this many entries, newest kept.
  THREAD_KEPT = 20

  # Kept without announcing, since posting the comment changed nothing a person reads of the finding. url is the comment's
  # page as the host gave it.
  def posted_on_line!(reference, url: nil) = update_columns({ host_comment_id: reference, host_comment_url: url.presence, updated_at: Time.current }.compact)

  # A finding with no comment of its own on a line opens where it was posted, such as the review's body.
  def posted_at!(url) = (update_columns(host_comment_url: url, updated_at: Time.current) if url.present?)

  # The why and failure chain in code terms, for a public repository.
  def publicized!(why:, failure_chain:) = update_columns(public_why: why.presence, public_failure_chain: failure_chain.presence, updated_at: Time.current)

  # Whether this finding was posted somewhere people read it.
  def posted? = host_comment_id.present? || host_comment_url.present?

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

  # Handed back when the check of a push could not run, so a retry takes it.
  def release_recheck!(sha) = self.class.where(id: id, rechecked_sha: sha).update_all(rechecked_sha: nil, updated_at: Time.current)

  # Handed back when a reply could not be answered, so a retry takes it.
  def release_answer!(comment)
    self.class.where(id: id).update_all([ "answered_comment_ids = answered_comment_ids - ?, updated_at = ?", comment.to_s, Time.current ])
  end

  # One thing said on the thread, by a person or by Halon, appended in SQL so two said at once are both kept.
  def said!(comment:, author:, body:, halon: false)
    entry = { "comment" => comment&.to_s, "author" => author.to_s, "body" => body.to_s.truncate(4_000), "halon" => halon }
    self.class.where(id: id).update_all([ "thread_said = thread_said || ?::jsonb, updated_at = ?", [ entry ].to_json, Time.current ])
  end

  # A reply Halon could not post on the thread or in the pull request's conversation, kept with why so the review's page
  # still shows it. Appended in SQL, like what was said.
  def unposted_reply!(body:, reason:)
    entry = { "body" => body.to_s.truncate(4_000), "reason" => reason.to_s, "at" => Time.current.utc.iso8601 }
    self.class.where(id: id).update_all([ "unposted_replies = unposted_replies || ?::jsonb, updated_at = ?", [ entry ].to_json, Time.current ])
  end

  # Every comment on the thread a reply could answer: the one that started it and each said on it since.
  def thread_comments = [ host_comment_id, *Array(thread_said).filter_map { |entry| entry["comment"] } ].compact_blank

  # The thread so far as the model reads it, oldest first.
  def thread_so_far
    Array(thread_said).last(THREAD_KEPT).map { |entry| "#{entry['halon'] ? 'Halon' : (entry['author'].presence || 'Someone')}: #{entry['body']}" }.join("\n\n")
  end

  # The finding as Halon posted it, for the model that checks a fix or answers a reply.
  def as_posted = PullRequestReview::Comments.new(hides: false).finding(self)
end
