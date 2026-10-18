# Tells a workspace's admins, once, that a scheduled check paused because its owner left.
class CheckOwnerGoneJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(check_id)
    check = Investigation::Check.find(check_id)
    return unless check.claim_owner_gone_notice!

    CheckOwnerNotice.new(check).tell_admins!
  end
end
