class IncidentUpdateWorkflow < SolidWorkflow::Base
  workflow_name "incident.incident_update.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_update_message
  step :post_announcement_thread

  def update_channel_topic(workflow:, step:, input:)
    service(workflow).update_channel_topic(workflow.subject)
  end

  def update_quick_actions(workflow:, step:, input:)
    service(workflow).update_quick_actions(workflow.subject)
  end

  def update_announcement(workflow:, step:, input:)
    service(workflow).update_announcement(workflow.subject)
  end

  def post_update_message(workflow:, step:, input:)
    checkpointed(step) do
      service(workflow).post_incident_update_message(
        workflow.subject,
        **update_params(workflow)
      )
    end
  end

  def post_announcement_thread(workflow:, step:, input:)
    checkpointed(step) do
      service(workflow).post_incident_update_announcement_thread(
        workflow.subject,
        **update_params(workflow)
      )
    end
  end

  private

  def update_params(workflow)
    {
      message: workflow.context["message"],
      updated_by_platform_user_id: workflow.context["updated_by_platform_user_id"],
      previous_status_name: workflow.context["previous_status_name"],
      previous_severity_name: workflow.context["previous_severity_name"],
      previous_type_name: workflow.context["previous_type_name"]
    }
  end

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
