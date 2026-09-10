# A canceled incident was never an incident, so it gets the closing
# announcement and archival, never the runbook attachment an update runs.
class IncidentCancelWorkflow < SolidWorkflow::Base
  workflow_name "incident.cancel.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_update_message
  step :post_announcement_thread
  step :note_milestones

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
      service(workflow).post_incident_update_message(workflow.subject, **update_params(workflow))
    end
  end

  def post_announcement_thread(workflow:, step:, input:)
    checkpointed(step) do
      service(workflow).post_incident_update_announcement_thread(workflow.subject, **update_params(workflow))
    end
  end

  # Runs last so the channel has already been told the incident is over.
  # A build without the AI engine skips it.
  def note_milestones(workflow:, step:, input:)
    return unless defined?(FirefightAi)

    MilestoneNotingJob.perform_later(workflow.subject.id)
  end

  private

  def update_params(workflow)
    {
      message: workflow.context["message"],
      updated_by_platform_user_id: workflow.context["updated_by_platform_user_id"],
      previous_status_name: workflow.context["previous_status_name"],
      previous_severity_name: nil,
      previous_type_name: nil
    }
  end

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
