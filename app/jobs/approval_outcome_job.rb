# A call an approval let through ended, so the messages that asked its approvers are redrawn to say how it went.
class ApprovalOutcomeJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    approval = Ability::Approval.find_by(id: approval_id)
    ApprovalNotificationService.mark_resolved!(approval) if approval&.notifications.present?
  end
end
