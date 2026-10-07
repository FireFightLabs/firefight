# An approved call that waits for a person to run it expires once its window passes, and whoever asked is told.
class ApprovedCallExpiryJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    approval = Ability::Approval.find_by(id: approval_id)
    return unless approval&.approved? && approval.consumed_at.nil? && approval.run_expires_at

    # Run a moment early by the queue, so it looks again once the window has passed.
    return self.class.set(wait_until: approval.run_expires_at).perform_later(approval.id) unless approval.run_lapsed?

    ApprovalResumption.lapsed!(approval) if approval.lapse_run!
  end
end
