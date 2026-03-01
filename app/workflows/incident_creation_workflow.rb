class IncidentCreationWorkflow < SolidWorkflow::Base
  workflow_name "incident.creation.v1"

  step :create_slack_channel
  step :set_channel_metadata, depends_on: [ :create_slack_channel ]
  step :post_quick_actions_message, depends_on: [ :set_channel_metadata ]
  step :post_announcement, depends_on: [ :create_slack_channel ]
  step :invite_declarer, depends_on: [ :post_quick_actions_message ]
  step :create_incident_event

  def create_slack_channel(workflow:, step:, input:)
    service(workflow).create_channel(workflow.subject)
  end

  def set_channel_metadata(workflow:, step:, input:)
    service(workflow).set_channel_metadata(workflow.subject)
  end

  def post_quick_actions_message(workflow:, step:, input:)
    service(workflow).post_quick_actions_message(workflow.subject)
  end

  def post_announcement(workflow:, step:, input:)
    service(workflow).post_announcement(workflow.subject)
  end

  def invite_declarer(workflow:, step:, input:)
    service(workflow).invite_declarer(workflow.subject)
  end

  def create_incident_event(workflow:, step:, input:)
    service(workflow).create_incident_event(workflow.subject)
  end

  private

  def service(workflow)
    @service ||= IncidentCreationService.new(workflow.subject.workspace)
  end
end
