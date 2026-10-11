require "test_helper"

# What an on-call tool's webhook sends back about its pages, end to end from the alert source's address.
class Api::V1::OnCallWebhooksTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include PagingTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @pagerduty = connect_pagerduty!(@workspace)
    @source = pagerduty_source!(@workspace)
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(priority: 1, conditions: [], outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE })
    stub_successful_slack_workflow
    IncidentCloseWorkflow.stubs(:start!)
  end

  test "the incident PagerDuty opened for a page Firefight raised joins the incident it was raised for rather than opening another" do
    page = raised_page(external_id: nil)

    assert_no_difference -> { @workspace.incidents.count } do
      deliver_alert!(@source, pagerduty_event("incident.triggered", incident_key: page.key))
    end

    assert_response :success
    assert_equal @incident, @source.alerts.sole.incident
    assert_equal "PGR0VU2", page.reload.external_id
    assert_equal [ page ], @incident.pages.to_a, "the alert is the same page, not a second one"
  end

  test "an acknowledgement, a note and an escalation in PagerDuty reach the incident's timeline, and the ping is still only accepted" do
    raised_page

    perform_enqueued_jobs(only: OnCallEventJob) do
      deliver_alert!(@source, pagerduty_event("incident.acknowledged"))
      deliver_alert!(@source, pagerduty_event("incident.annotated", note: "Rolled back"))
      deliver_alert!(@source, pagerduty_event("incident.escalated"))
    end

    assert_response :success
    assert_equal [ IncidentEvent::PAGE_ACKNOWLEDGED, IncidentEvent::PAGE_NOTED, IncidentEvent::PAGE_ESCALATED ],
                 @incident.incident_events.where(event_type: IncidentEvent::PAGE_EVENTS).order(:created_at).pluck(:event_type)
    assert_equal 0, @source.alerts.count
  end

  test "a person resolving the page in PagerDuty resolves the alert and the incident, and Firefight sends nothing back" do
    page = raised_page
    deliver_alert!(@source, pagerduty_event("incident.triggered"))
    Integrations::PagerdutyApi.any_instance.expects(:update_status).never

    perform_enqueued_jobs(only: [ OnCallEventJob, OnCallSyncJob ]) { deliver_alert!(@source, pagerduty_event("incident.resolved")) }

    assert_equal Alert::STATUS_RESOLVED, @source.alerts.sole.status
    assert @incident.reload.closed?
    assert_equal Incident::Page::STATE_RESOLVED, page.reload.state
  end

  test "an Opsgenie acknowledgement and note reach the incident, and a close by a rule leaves it open" do
    opsgenie = connect_opsgenie!(@workspace)
    source = opsgenie_source!(@workspace)
    @incident.pages.create!(workspace: @workspace, integration: opsgenie, origin: Incident::Page::ORIGIN_RAISED, state: Incident::Page::STATE_TRIGGERED,
                            external_id: "70413a06-38d6-4c85-92b8-5ebc900d42e2", target: "team: Platform")

    perform_enqueued_jobs(only: OnCallEventJob) do
      deliver_alert!(source, opsgenie_action("Acknowledge"))
      deliver_alert!(source, opsgenie_action("AddNote", note: "On it"))
      deliver_alert!(source, opsgenie_action("Close", username: "System"))
    end

    assert_equal workspace_memberships(:bob_workspace_one), @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_ACKNOWLEDGED).actor
    assert_equal "On it", @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_NOTED).metadata["message"]
    assert @incident.incident_events.exists?(event_type: IncidentEvent::PAGE_RESOLVED)
    assert_not @incident.reload.terminal?
  end

  private

  def raised_page(external_id: "PGR0VU2")
    @incident.pages.create!(workspace: @workspace, integration: @pagerduty, origin: Incident::Page::ORIGIN_RAISED, state: Incident::Page::STATE_TRIGGERED,
                            external_id: external_id, reference: "#42", target: "Checkout")
  end
end
