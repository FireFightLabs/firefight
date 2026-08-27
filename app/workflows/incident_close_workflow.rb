class IncidentCloseWorkflow < SolidWorkflow::Base
  workflow_name "incident.close.v1"

  step :update_channel_topic
  step :update_quick_actions
  step :update_announcement
  step :post_resolution_message
  step :post_resolution_announcement_thread
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

  def post_resolution_message(workflow:, step:, input:)
    checkpointed(step) do
      service(workflow).post_resolution_message(
        workflow.subject,
        resolved_by_platform_user_id: workflow.context["resolved_by_platform_user_id"]
      )
    end
  end

  def post_resolution_announcement_thread(workflow:, step:, input:)
    checkpointed(step) do
      service(workflow).post_resolution_announcement_thread(
        workflow.subject,
        resolved_by_platform_user_id: workflow.context["resolved_by_platform_user_id"]
      )
    end
  end

  # Last, so the channel has already been told the incident is over. The pass
  # reads the transcript and writes what the team worked out onto the
  # timeline. Nothing is posted, and a build without the AI engine skips it.
  def note_milestones(workflow:, step:, input:)
    return unless defined?(FirefightAi)

    MilestoneNotingJob.perform_later(workflow.subject.id)
  end

  private

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
