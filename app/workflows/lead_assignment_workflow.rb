class LeadAssignmentWorkflow < SolidWorkflow::Base
  workflow_name "incident.lead_assignment.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  # A lead outside the channel sees nothing of the incident, so a failure here leaves the rest of the steps to carry on.
  step :invite_lead, on_failure: SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  # The platform may refuse a message only the lead sees while they are outside the channel, and that refusal must not
  # cancel the announcement.
  step :post_lead_expectations, depends_on: [ :update_channel_topic, :invite_lead ], on_failure: SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  step :post_lead_announcement, depends_on: [ :update_channel_topic, :invite_lead ]

  def update_channel_topic(workflow:, step:, input:)
    service(workflow).update_channel_topic(workflow.subject)
  end

  def update_quick_actions(workflow:, step:, input:)
    service(workflow).update_quick_actions(workflow.subject)
  end

  def update_announcement(workflow:, step:, input:)
    service(workflow).update_announcement(workflow.subject)
  end

  # A lead with no platform account has nobody to invite. Someone already in the channel is left as they are.
  def invite_lead(workflow:, step:, input:)
    lead_platform_user_id = workflow.context["lead_platform_user_id"]
    return { skipped: true } if lead_platform_user_id.blank?

    incident = workflow.subject
    result = IncidentInviteService.new(incident.workspace).invite!(incident: incident, people: [ lead_platform_user_id ])
    if result.failed.any?
      checkpointed(step) do
        incident.workspace.adapter.post_lead_invite_failed(
          channel_id: incident.channel_id,
          lead_platform_user_id: lead_platform_user_id,
          lead_name: workflow.context["lead_name"]
        )
      end
    end

    { invited: result.invited.size, already_in_channel: result.already_in_channel.size, failed: result.failed.size }
  end

  # A lead with no platform account has nobody to show the expectations to. An ephemeral reaches only someone in the
  # channel, so it is skipped unless the invite reported nobody failed. A raised invite leaves no output, so it skips too.
  def post_lead_expectations(workflow:, step:, input:)
    return { skipped: true } if workflow.context["lead_platform_user_id"].blank?
    return { skipped: true } unless input.dig("invite_lead", "failed") == 0

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
