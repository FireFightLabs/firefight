# Tells a workspace's admins, once, that a scheduled check paused because its owner left.
class CheckOwnerGoneJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(check_id)
    check = Investigation::Check.find(check_id)
    claimed_at = check.claim_owner_gone_notice!
    return unless claimed_at

    check.release_owner_gone_notice!(claimed_at) if CheckOwnerNotice.new(check).tell_admins!
  end
end
