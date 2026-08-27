class AbilityApprovalNotificationJob < ApplicationJob
  queue_as :default

  def perform(approval_id:)
    approval = Ability::Approval.find_by(id: approval_id)
    return unless approval&.pending?

    ApprovalNotificationService.post!(approval)
  end
end
