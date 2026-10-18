# A scheduled check runs in its owner's name, so a run reads no further than they could (Investigation#acting_principal).
# The owner starts as whoever made it. An owner who leaves pauses the check, in one guarded update, until an admin gives
# it to another member, and the admins are told once.
module Investigation::Check::Ownership
  extend ActiveSupport::Concern

  FORMER_MEMBER = "a former member".freeze
  # How many times the admins are tried for one pause before Firefight stops, so a platform that keeps failing is never
  # asked forever.
  NOTICE_ATTEMPTS = 5

  included do
    belongs_to :owner, class_name: "WorkspaceMembership", optional: true

    before_validation :owned_by_creator, on: :create

    # Paused for want of an owner, with the admins not told yet.
    scope :untold_pauses, -> { active.where.not(paused_at: nil).where(owner_gone_told_at: nil) }
    # Running in the name of someone who left or no longer exists, whatever their schedule.
    scope :owned_by_gone, -> {
      active.where(paused_at: nil).left_joins(:owner).where(owner_id: nil).or(
        active.where(paused_at: nil).left_joins(:owner).where.not(workspace_memberships: { removed_at: nil })
      )
    }
  end

  class_methods do
    # Gives every check with no owner its creator, and pauses one whose creator is gone. Run once, by the move to owners.
    def adopt_creators!
      where(owner_id: nil).where.not(created_by_id: nil).update_all("owner_id = created_by_id")
      includes(owner: :user).find_each { |check| check.pause_for_gone_owner! if check.owner_gone? }
    end
  end

  def paused? = paused_at.present?

  # Gone once removed, or deleted outright, which leaves no owner at all.
  def owner_gone? = owner.nil? || owner.removed?

  # Pauses the check for an owner who left, once, naming them for the admins. Guarded on the owner it read too, so a pause
  # never lands on a check an admin handed to someone else meanwhile. False when it moved nothing.
  def pause_for_gone_owner!(now = Time.current)
    paused = self.class.where(id: id, paused_at: nil, owner_id: owner_id)
                 .update_all(paused_at: now, paused_owner_name: owner&.display_name, owner_gone_told_at: nil, owner_gone_notice_attempts: 0,
                             updated_at: now) > 0
    reload if paused
    paused
  end

  # Takes the one telling of the admins, answering the time it was taken. Nil when someone already told them, or it is no
  # longer paused.
  def claim_owner_gone_notice!(now = Time.current)
    claimed = self.class.where(id: id, owner_gone_told_at: nil).where.not(paused_at: nil)
                  .update_all([ "owner_gone_told_at = ?, owner_gone_notice_attempts = owner_gone_notice_attempts + 1, updated_at = ?", now, now ]) > 0
    now if claimed
  end

  # Gives back a telling no admin received, so the next sweep tries again. Only the claim made at claimed_at, so a failed
  # job never clears a newer one, such as after the check was handed on and paused again.
  # A telling tried NOTICE_ATTEMPTS times keeps its claim, so the admins are not tried again.
  def release_owner_gone_notice!(claimed_at, now = Time.current)
    self.class.where(id: id, owner_gone_told_at: claimed_at).where.not(paused_at: nil).where(owner_gone_notice_attempts: ...NOTICE_ATTEMPTS)
              .update_all(owner_gone_told_at: nil, updated_at: now)
  end

  def paused_because
    return nil unless paused?

    "#{name} (owned by #{paused_owner_name.presence || FORMER_MEMBER}, who left) is paused. Give it a new owner to resume."
  end

  def hand_to_blocked_reason(member)
    return "Choose a member of this workspace." unless member && member.workspace_id == workspace_id
    return "#{member.display_name} is not a member of this workspace any more." if member.removed?

    nil
  end

  # Gives the check to member and resumes it, running next at its time rather than for every time it missed. Guarded on
  # the owner it read, so two handovers, or a handover and a pause, never cross. False when the owner changed meanwhile.
  def hand_to!(member, now = Time.current)
    blocked = hand_to_blocked_reason(member)
    raise ArgumentError, blocked if blocked

    moved = self.class.where(id: id, owner_id: owner_id)
                .update_all(owner_id: member.id, paused_at: nil, paused_owner_name: nil, owner_gone_told_at: nil, owner_gone_notice_attempts: 0,
                            next_run_at: next_run_after(now), updated_at: now) > 0
    reload if moved
    moved
  end

  private

  def owned_by_creator
    self.owner ||= created_by
  end
end
