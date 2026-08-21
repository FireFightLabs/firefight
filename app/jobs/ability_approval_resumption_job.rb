class AbilityApprovalResumptionJob < ApplicationJob
  queue_as :default

  def perform(approval_id:)
    approval = Ability::Approval.find_by(id: approval_id)
    return unless approval

    approval.approved? ? ApprovalResumption.resume!(approval) : ApprovalResumption.decline!(approval)
  end
end
