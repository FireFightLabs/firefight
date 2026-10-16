class IncidentCreationWorkflow < SolidWorkflow::Base
  workflow_name "incident.creation.v1"

  step :create_slack_channel
  step :set_channel_metadata, depends_on: [ :create_slack_channel ]
  step :post_quick_actions_message, depends_on: [ :set_channel_metadata ]
  # Last in the channel, once everything else that speaks in or fills it has finished, whether it worked or not.
  step :post_first_incident_walkthrough, depends_on: [
    :post_quick_actions_message, :invite_declarer, :invite_responders, :attach_runbooks, :post_carried_over_investigation,
    :start_alert_investigation
  ]
  step :post_announcement, depends_on: [ :create_slack_channel ]
  # A failure in any of these leaves the rest of the setup and the guide to carry on.
  step :invite_declarer, depends_on: [ :post_quick_actions_message ], on_failure: SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  step :invite_responders, depends_on: [ :create_slack_channel ], on_failure: SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  step :attach_runbooks, depends_on: [ :post_quick_actions_message ], on_failure: SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  step :post_carried_over_investigation, depends_on: [ :post_quick_actions_message ], on_failure: SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  step :start_alert_investigation, depends_on: [ :post_quick_actions_message ], on_failure: SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  step :create_incident_event

  # The run has not yet reached its walkthrough step, so the guide is still this run's to post.
  def self.opening?(incident)
    SolidWorkflow::Step.pending.where(
      name: "post_first_incident_walkthrough",
      workflow: SolidWorkflow::Workflow.live.where(subject: incident, workflow_class: name)
    ).exists?
  end

  def create_slack_channel(workflow:, step:, input:)
    service(workflow).create_channel(workflow.subject)
  end

  def set_channel_metadata(workflow:, step:, input:)
    service(workflow).set_channel_metadata(workflow.subject)
  end

  def post_quick_actions_message(workflow:, step:, input:)
    service(workflow).post_quick_actions_message(workflow.subject)
  end

  def post_first_incident_walkthrough(workflow:, step:, input:)
    checkpointed(step) do
      OnboardingWalkthroughService.new(workflow.subject.workspace).advance!(workflow.subject)
    end
  end

  def post_announcement(workflow:, step:, input:)
    service(workflow).post_announcement(workflow.subject)
  end

  def invite_declarer(workflow:, step:, input:)
    service(workflow).invite_declarer(workflow.subject)
  end

  def invite_responders(workflow:, step:, input:)
    service(workflow).invite_members(workflow.subject, workflow.context["invite_membership_ids"])
  end

  # Posted once, since a retried step would post the answer twice.
  def post_carried_over_investigation(workflow:, step:, input:)
    checkpointed(step) { service(workflow).post_carried_over_investigation(workflow.subject) }
  end

  # Once the channel is there for the run to speak in. Checkpointed, so a retried step never starts a second run after
  # the first finished.
  def start_alert_investigation(workflow:, step:, input:)
    { "outcome" => checkpointed(step) { Investigation::AlertStart.start!(workflow.subject) } }
  end

  def attach_runbooks(workflow:, step:, input:)
    RunbookAttachmentService.new(workflow.subject.workspace).auto_attach(workflow.subject)
  end

  def create_incident_event(workflow:, step:, input:)
    service(workflow).create_incident_event(workflow.subject)
  end

  private

  def service(workflow)
    @service ||= IncidentCreationService.new(workflow.subject.workspace)
  end
end
