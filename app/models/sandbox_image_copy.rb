# Who saves a provider's copy of one sandbox image version for one workspace, named as the provider keeps it. Only a
# box started ahead of need saves it (Provider#prepare_image!), never a run's, and one claim wins the save. A claim not
# finished within ABANDONED_AFTER, by a process that died, can be taken over.
class SandboxImageCopy < ApplicationRecord
  STATUS_UNCLAIMED = "unclaimed".freeze
  STATUS_SAVING = "saving".freeze
  STATUS_READY = "ready".freeze
  STATUS_FAILED = "failed".freeze
  STATUSES = [ STATUS_UNCLAIMED, STATUS_SAVING, STATUS_READY, STATUS_FAILED ].freeze
  # A claim made to prepare the copy ahead of need is held while a box starts and pulls the image, which a provider
  # allows up to 15 minutes, so a claim this old with no copy to show for it was let go of.
  ABANDONED_AFTER = 30.minutes

  validates :status, inclusion: { in: STATUSES }

  # Whether claimed_by, a box or a run preparing the copy, won the save. Only a claim no one holds, or one abandoned,
  # is taken, in one guarded update. A ready copy is claimable, since it is asked for only when the provider no longer
  # holds it.
  def self.claim!(provider, name, claimed_by)
    row = create_or_find_by!(provider: provider, name: name)
    now = Time.current
    where(id: row.id)
      .where("status IN (:open) OR (status = :saving AND claimed_at < :abandoned)",
             open: [ STATUS_UNCLAIMED, STATUS_FAILED, STATUS_READY ], saving: STATUS_SAVING, abandoned: ABANDONED_AFTER.before(now))
      .update_all(status: STATUS_SAVING, claimed_by: claimed_by, claimed_at: now, updated_at: now) == 1
  end

  # The claim claimed_by holds let go of, so a later box can claim the save again.
  def self.failed!(provider, name, claimed_by)
    where(provider: provider, name: name, status: STATUS_SAVING, claimed_by: claimed_by).update_all(status: STATUS_FAILED, updated_at: Time.current)
  end

  def self.ready!(provider, name)
    where(provider: provider, name: name).where.not(status: STATUS_READY).update_all(status: STATUS_READY, updated_at: Time.current)
  end

  # Rows for the provider's image versions other than the one it runs now, whose copies are all named from prefix.
  def self.forget_others!(provider, prefix) = where(provider: provider).where.not("name LIKE ?", "#{sanitize_sql_like(prefix)}%").delete_all
end
