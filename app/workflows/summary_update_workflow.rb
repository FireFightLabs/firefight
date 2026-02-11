class SummaryUpdateWorkflow < Base
  workflow_name "incident.summary_update.v1"

  step :update_quick_actions
  step :update_announcement
  step :post_confirmation

  def update_quick_actions(workflow:, step:, input:)
    service(workflow).update_quick_actions(workflow.subject)
  end

  def update_announcement(workflow:, step:, input:)
    service(workflow).update_announcement(workflow.subject)
  end

  def post_confirmation(workflow:, step:, input:)
    adapter = WorkspaceAdapter.for(workflow.subject.workspace)
    adapter.post_message(
      channel_id: workflow.subject.slack_channel_id,
      text: "Summary updated by <@#{workflow.context["updated_by_platform_user_id"]}>",
      blocks: nil
    )
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
