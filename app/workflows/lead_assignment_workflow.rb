class LeadAssignmentWorkflow < SolidWorkflow::Base
  workflow_name "incident.lead_assignment.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_lead_expectations, depends_on: [ :update_channel_topic ]
  step :post_lead_announcement, depends_on: [ :update_channel_topic ]

  def update_channel_topic(workflow:, step:, input:)
    service(workflow).update_channel_topic(workflow.subject)
  end

  def update_quick_actions(workflow:, step:, input:)
    service(workflow).update_quick_actions(workflow.subject)
  end

  def update_announcement(workflow:, step:, input:)
    service(workflow).update_announcement(workflow.subject)
  end

  # A lead with no platform account has nobody to show the expectations to.
  def post_lead_expectations(workflow:, step:, input:)
    return { skipped: true } if workflow.context["lead_platform_user_id"].blank?

    checkpointed(step) do
      workflow.subject.workspace.adapter.post_lead_expectations(
        channel_id: workflow.subject.channel_id,
        user_id: workflow.context["lead_platform_user_id"]
      )
    end
  end

  def post_lead_announcement(workflow:, step:, input:)
    checkpointed(step) do
      workflow.subject.workspace.adapter.post_lead_announcement(
        channel_id: workflow.subject.channel_id,
        lead_platform_user_id: workflow.context["lead_platform_user_id"],
        lead_name: workflow.context["lead_name"]
      )
    end
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
