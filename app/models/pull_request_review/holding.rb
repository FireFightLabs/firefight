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

  # A post that waits behind the held one, such as a reply on a thread, kept in SQL so two kept at once are both kept. An
  # edit of a finding's comments is kept once, since catching up writes the finding as it stands then.
  def wait!(post)
    post = post.stringify_keys
    if post["kind"] == PENDING_EDIT
      self.class.where(id: id).where.not("pending_posts @> ?::jsonb", [ post ].to_json)
          .update_all([ "pending_posts = pending_posts || ?::jsonb, updated_at = ?", [ post ].to_json, Time.current ])
    else
      self.class.where(id: id).update_all([ "pending_posts = pending_posts || ?::jsonb, updated_at = ?", [ post ].to_json, Time.current ])
    end
  end

  # Takes every post that waited, oldest first, so a second catch up never posts one again.
  def take_pending!
    transaction do
      locked = self.class.lock.find(id)
      taken = Array(locked.pending_posts)
      locked.update_columns(pending_posts: [], updated_at: Time.current) if taken.any?
      taken
    end
  end

  PENDING_REPLY = "reply".freeze
  PENDING_RESOLVE = "resolve".freeze
  PENDING_EDIT = "edit".freeze

  private

  def plain(given) = given.transform_values { |value| value.is_a?(Array) ? value.map { |each| each.respond_to?(:to_h) ? each.to_h : each } : value }
end
