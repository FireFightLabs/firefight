class IncidentEscalationWorkflow < SolidWorkflow::Base
  workflow_name "incident.escalation.v1"

  step :post_escalation_message
  step :post_escalation_announcement_thread
  step :post_escalation_direct_message

  def post_escalation_message(workflow:, step:, input:)
    service(workflow).post_escalation_message(
      workflow.subject,
      escalated_by_platform_user_id: workflow.context["escalated_by_platform_user_id"],
      escalated_to_platform_user_id: workflow.context["escalated_to_platform_user_id"],
      reason: workflow.context["reason"]
    )
  end

  def post_escalation_announcement_thread(workflow:, step:, input:)
    service(workflow).post_escalation_announcement_thread(
      workflow.subject,
      escalated_by_platform_user_id: workflow.context["escalated_by_platform_user_id"],
      escalated_to_platform_user_id: workflow.context["escalated_to_platform_user_id"],
      reason: workflow.context["reason"]
    )
  end

  def post_escalation_direct_message(workflow:, step:, input:)
    service(workflow).post_escalation_direct_message(
      workflow.subject,
      escalated_by_platform_user_id: workflow.context["escalated_by_platform_user_id"],
      escalated_to_platform_user_id: workflow.context["escalated_to_platform_user_id"],
      escalation_event_id: workflow.context["escalation_event_id"],
      reason: workflow.context["reason"]
    )
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
