require "test_helper"

class Operator::IncidentProcessTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    @workflow = SolidWorkflow::Workflow.create!(
      name: "incident.creation.v1", workflow_class: "IncidentCreationWorkflow", subject: @incident, state: "failed"
    )
    @failed = @workflow.steps.create!(name: "invite_responders", position: 1, status: "failed", attempts: 3, max_attempts: 3,
                                      last_error: "AdapterError::NotInChannel: not_in_channel", started_at: 2.minutes.ago, completed_at: 1.minute.ago)
    @workflow.steps.create!(name: "create_slack_channel", position: 0, status: "succeeded", started_at: 3.minutes.ago, completed_at: 3.minutes.ago + 1.second)
  end

  test "a failed step is on the timeline with its error and a way to run it again" do
    entry = process.entries.find { |candidate| candidate.key == "step-#{@failed.id}" }

    assert_equal Operator::IncidentProcess::TONE_BAD, entry.tone
    assert_equal @failed.id, entry.retry_step_id
    assert_match "not_in_channel", entry.technical
    assert_match "attempt 3 of 3", entry.detail
  end

  test "a failed Slack call in the incident's channel, and a failed webhook, are on it too, the webhook with a way to send again" do
    PlatformCallFailure.create!(workspace: @incident.workspace, platform: Platforms::SLACK, operation: "chat.postMessage",
                                error_class: "AdapterError::NotInChannel", channel_id: @incident.channel_id)
    event = @incident.incident_events.create!(event_type: IncidentEvent::MILESTONE_NOTED, metadata: { statement: "x" })
    webhook = @incident.workspace.webhooks.create!(name: "Acme", url: "https://hooks.acme.dev/in", subscribed_events: [ IncidentEvent::INCIDENT_CREATED ])
    delivery = WebhookDelivery.create!(webhook: webhook, incident_event: event, event_type: IncidentEvent::INCIDENT_CREATED,
                                       signed_payload: "{}", state: :failed, attempts: 5, response_code: 502, error_message: "502 Bad Gateway")

    kinds = process.entries.map(&:kind)
    assert_includes kinds, Operator::IncidentProcess::KIND_PLATFORM
    hook = process.entries.find { |entry| entry.key == "delivery-#{delivery.id}" }
    assert_equal delivery.id, hook.redeliver_id
    assert_match "HTTP 502", hook.detail
  end

  test "the list counts each incident's failed records" do
    before = Operator::IncidentProcess.problem_counts([ @incident ])[@incident.id]

    @workflow.steps.create!(name: "post_announcement", position: 2, status: "failed", attempts: 5)

    assert_equal before + 1, Operator::IncidentProcess.problem_counts([ @incident ])[@incident.id]
  end

  private

  def process = Operator::IncidentProcess.new(@incident)
end
