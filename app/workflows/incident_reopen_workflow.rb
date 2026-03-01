class IncidentReopenWorkflow < SolidWorkflow::Base
  workflow_name "incident.reopen.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_reopen_message
  step :post_reopen_announcement_thread

  def update_channel_topic(workflow:, step:, input:)
    service(workflow).update_channel_topic(workflow.subject)
  end

  def update_quick_actions(workflow:, step:, input:)
    service(workflow).update_quick_actions(workflow.subject)
  end

  def update_announcement(workflow:, step:, input:)
    service(workflow).update_announcement(workflow.subject)
  end

  def post_reopen_message(workflow:, step:, input:)
    service(workflow).post_reopen_message(
      workflow.subject,
      reopened_by_platform_user_id: workflow.context["reopened_by_platform_user_id"],
      reason: workflow.context["reason"]
    )
  end

  def post_reopen_announcement_thread(workflow:, step:, input:)
    service(workflow).post_reopen_announcement_thread(
      workflow.subject,
      reopened_by_platform_user_id: workflow.context["reopened_by_platform_user_id"],
      reason: workflow.context["reason"]
    )
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
