# Redraws every message an approval was asked in once it no longer waits, such as a workflow's request withdrawn because
# it went stale.
class AbilityApprovalResolvedJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    approval = Ability::Approval.find_by(id: approval_id)
    ApprovalNotificationService.mark_resolved!(approval) if approval
  end
end
