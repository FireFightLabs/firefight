class IncidentCloseWorkflow < Base
  workflow_name "incident.close.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_resolution_message
  step :post_resolution_announcement_thread

  def update_channel_topic(workflow:, step:, input:)
    service(workflow).update_channel_topic(workflow.subject)
  end

  def update_quick_actions(workflow:, step:, input:)
    service(workflow).update_quick_actions(workflow.subject)
  end

  def update_announcement(workflow:, step:, input:)
    service(workflow).update_announcement(workflow.subject)
  end

  def post_resolution_message(workflow:, step:, input:)
    service(workflow).post_resolution_message(
      workflow.subject,
      resolved_by_platform_user_id: workflow.context["resolved_by_platform_user_id"]
    )
  end

  def post_resolution_announcement_thread(workflow:, step:, input:)
    service(workflow).post_resolution_announcement_thread(
      workflow.subject,
      resolved_by_platform_user_id: workflow.context["resolved_by_platform_user_id"]
    )
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
