# A post an approval rule held. The review keeps that one approval, and nothing else is posted for it until the approval
# is decided, so one review never holds two. The approval keeps the call exactly as it was held and what to record once
# it runs, which ApprovalResumption hands back.
module PullRequestReview::Holding
  extend ActiveSupport::Concern

  RESUME_KIND = "pull_request_review_post".freeze

  # One held call: the operation, its arguments with any line comments as plain values, and what it records.
  HeldPost = Data.define(:operation, :given, :purpose)

  # Whether a post is waiting on an approval. One no longer pending, decided or lapsed, stops holding.
  def holding?
    return false if held_approval_id.blank?

    approval = workspace.ability_approvals.find_by(id: held_approval_id)
    return true if approval&.pending?

    release_held!(held_approval_id) unless approval&.usable?
    approval&.usable? || false
  end

  # Parks the posting on approval, in one guarded update so a second held call never replaces the first.
  def hold!(approval, operation:, given:, purpose:)
    approval.update!(resume_payload: { kind: RESUME_KIND, review_id: id, operation: operation.to_s, given: plain(given), purpose: purpose })
    self.class.where(id: id, held_approval_id: nil).update_all(held_approval_id: approval.id, updated_at: Time.current)
    reload
  end

  def release_held!(approval_id)
    self.class.where(id: id, held_approval_id: approval_id).update_all(held_approval_id: nil, updated_at: Time.current)
    reload
  end

  # The call an approval holds for this review, or nil when it holds none.
  def held_post(approval_id)
    payload = workspace.ability_approvals.find_by(id: approval_id)&.resume_payload.to_h
    return unless payload["kind"] == RESUME_KIND && payload["review_id"] == id

    HeldPost.new(operation: payload["operation"].to_sym, given: payload["given"].to_h.symbolize_keys, purpose: payload["purpose"].to_h)
  end

  # A post that waits behind the held one, such as a reply on a thread. It is kept only while a post is still held,
  # checked in the same locked transaction, so a post made just after the hold ended is sent rather than left waiting.
  # An edit of a finding's comments and a fix's check on a thread are kept once per finding, the newest, since catching
  # up writes the finding as it stands then. At most PENDING_KEPT wait, the oldest let go first. False when no post is
  # held any more.
  def wait!(post)
    post = post.stringify_keys
    transaction do
      locked = self.class.lock.find(id)
      return false if locked.held_approval_id.nil?

      kept = Array(locked.pending_posts).reject { |each| replaces?(post, each) } + [ post ]
      dropped = kept.size - PENDING_KEPT
      if dropped.positive?
        Rails.logger.warn({ event: "pull_request_review.pending_dropped", pull_request_review_id: id, dropped: dropped }.to_json)
        kept = kept.last(PENDING_KEPT)
      end
      locked.update_columns(pending_posts: kept, updated_at: Time.current)
      true
    end
  end

  # Ends the hold and hands back what waited behind it, oldest first, in one locked transaction, so nothing joins the
  # queue after it was read. Each post stays queued until it is sent (sent_pending!), so a worker that dies leaves the
  # rest for the next catch up.
  def release_with_pending!(approval_id = nil)
    transaction do
      locked = self.class.lock.find(id)
      locked.update_columns(held_approval_id: nil, updated_at: Time.current) if approval_id && locked.held_approval_id == approval_id
      reload
      Array(locked.pending_posts)
    end
  end

  # One post that waited, taken off the queue once it was sent, or once it was held again, which its approval replays.
  # Only the first entry equal to it goes, so a second reply with the same words stays queued until it is sent too.
  def sent_pending!(post)
    self.class.where(id: id).update_all([ <<~SQL.squish, post.to_json, Time.current ])
      pending_posts = (SELECT COALESCE(jsonb_agg(entry.value ORDER BY entry.position), '[]'::jsonb)
                       FROM jsonb_array_elements(pending_posts) WITH ORDINALITY AS entry(value, position)
                       WHERE entry.position <> COALESCE((SELECT MIN(first.position)
                                                         FROM jsonb_array_elements(pending_posts) WITH ORDINALITY AS first(value, position)
                                                         WHERE first.value = ?::jsonb), 0)),
      updated_at = ?
    SQL
  end

  # A waiting post stops the queue from holding a second copy of the same thing: the edit of one finding, or the check
  # of a push on one thread.
  def replaces?(post, waiting)
    return false unless waiting["finding_id"] == post["finding_id"] && waiting["kind"] == post["kind"]

    post["kind"] == PENDING_EDIT || (post["kind"] == PENDING_REPLY && post["recheck"] == true && waiting["recheck"] == true)
  end

  # How many posts may wait behind one held post.
  PENDING_KEPT = 50

  PENDING_REPLY = "reply".freeze
  PENDING_RESOLVE = "resolve".freeze
  PENDING_EDIT = "edit".freeze

  private

  def plain(given) = given.transform_values { |value| value.is_a?(Array) ? value.map { |each| each.respond_to?(:to_h) ? each.to_h : each } : value }
end
