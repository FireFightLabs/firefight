class SummaryUpdateWorkflow < SolidWorkflow::Base
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
    checkpointed(step) do
      workflow.subject.workspace.adapter.post_message(
        channel_id: workflow.subject.channel_id,
        text: ":memo: Summary updated by <@#{workflow.context["updated_by_platform_user_id"]}>",
        blocks: nil
      )
    end
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
