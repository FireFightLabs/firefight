# Which box saves a provider's copy of one sandbox image version, named as the provider keeps it. Boxes that start at
# once for a new version all find no copy, and only the one that claims it here saves it. The others pull the image
# and never save. A claim not finished within ABANDONED_AFTER, by a process that died, can be taken over.
class SandboxImageCopy < ApplicationRecord
  STATUS_UNCLAIMED = "unclaimed".freeze
  STATUS_SAVING = "saving".freeze
  STATUS_READY = "ready".freeze
  STATUS_FAILED = "failed".freeze
  STATUSES = [ STATUS_UNCLAIMED, STATUS_SAVING, STATUS_READY, STATUS_FAILED ].freeze
  # A claim is made by a box already up, just before it asks for the save, and a save under way is seen at the
  # provider, so a claim this old with no copy to show for it was let go of.
  ABANDONED_AFTER = 10.minutes

  validates :status, inclusion: { in: STATUSES }

  # Whether box_ref won the save. Only a claim no one holds, or one abandoned, is taken, in one guarded update. A ready
  # copy is claimable, since it is asked for only when the provider no longer holds it.
  def self.claim!(provider, name, box_ref)
    row = create_or_find_by!(provider: provider, name: name)
    now = Time.current
    where(id: row.id)
      .where("status IN (:open) OR (status = :saving AND claimed_at < :abandoned)",
             open: [ STATUS_UNCLAIMED, STATUS_FAILED, STATUS_READY ], saving: STATUS_SAVING, abandoned: ABANDONED_AFTER.before(now))
      .update_all(status: STATUS_SAVING, box_ref: box_ref, claimed_at: now, updated_at: now) == 1
  end

  # The claim box_ref holds let go of, so a later box can claim the save again.
  def self.failed!(provider, name, box_ref)
    where(provider: provider, name: name, status: STATUS_SAVING, box_ref: box_ref).update_all(status: STATUS_FAILED, updated_at: Time.current)
  end

  def self.ready!(provider, name)
    where(provider: provider, name: name).where.not(status: STATUS_READY).update_all(status: STATUS_READY, updated_at: Time.current)
  end

  # Rows for the provider's image versions other than the one it runs now.
  def self.forget_others!(provider, name) = where(provider: provider).where.not(name: name).delete_all
end
