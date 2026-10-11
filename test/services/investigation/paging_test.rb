require "test_helper"

class Investigation::PagingTest < ActiveSupport::TestCase
  include OnCallTestHelper
  include PagingTestHelper

  setup do
    alert_run_with_restart_fix
    @workspace.update!(on_call_paging_enabled: true)
    @bob = workspace_memberships(:bob_workspace_one)
    IncidentEscalationWorkflow.stubs(:start!)
  end

  test "a run an alert started names who is on call, and Firefight escalates the incident to them once with what Halon found" do
    page = @investigation.page_to("person" => @bob.user.email, "steps" => [ 1 ])
    @finding.update!(page_member: page.member)

    Investigation::Paging.page!(@investigation)
    Investigation::Paging.page!(@investigation.reload)

    event = @incident.incident_events.where(event_type: IncidentEvent::INCIDENT_ESCALATED).sole
    assert_equal [ @bob.id, SystemAgent.investigator ], [ event.metadata["escalated_to_member_id"], event.actor ]
    assert_match "Halon looked at this alert. web stopped answering", event.metadata["reason"]
    assert_match "Proposed fix, waiting for someone to apply it: Restart web", event.metadata["reason"]
    assert_equal [ @bob ], @incident.on_call_members
    ledger = @workspace.ability_invocations.find_by!(triggered_by_label: "Paging whoever is on call for #{@incident.identifier}")
    assert_equal [ SystemAgent.investigator, Ability::Invocation::OUTCOME_SUCCESS ], [ ledger.principal, ledger.outcome ]
  end

  test "nobody is paged while paging is off" do
    @finding.update!(page_member: @bob)
    @workspace.update!(on_call_paging_enabled: false)

    Investigation::Paging.page!(@investigation.reload)

    assert_empty @incident.incident_events.where(event_type: IncidentEvent::INCIDENT_ESCALATED)
  end

  test "a run names only a member it showed is on call, and only when it may page" do
    error = assert_raises(Investigation::PageRefused) { @investigation.page_to("person" => "nobody@example.com", "steps" => [ 1 ]) }
    assert_match "who is not a member of this workspace", error.message
    assert_match "cites no step", assert_raises(Investigation::PageRefused) { @investigation.page_to("person" => @bob.user.email, "steps" => []) }.message

    @workspace.update!(on_call_paging_enabled: false)
    assert_match "Leave page out", assert_raises(Investigation::PageRefused) { @investigation.reload.page_to("person" => @bob.user.email, "steps" => [ 1 ]) }.message
  end

  test "with PagerDuty connected the page is raised on the service the run named, and nobody is escalated to here" do
    pagerduty = connect_pagerduty!(@workspace)
    Integrations::PagerdutyApi.any_instance.stubs(:services).returns([ { "id" => "PF9KMXH", "name" => "Checkout" } ])
    Integrations::PagerdutyApi.any_instance.expects(:create_incident).with { |details:, **| details.start_with?("Halon looked at this alert.") }
                .returns(pagerduty_incident)
    ask = @investigation.page_to("person" => "oncall@acme.io", "steps" => [ 1 ], "target" => "Checkout")
    assert_equal [ nil, "oncall@acme.io", pagerduty, "Checkout" ], [ ask.member, ask.email, ask.integration, ask.target ]
    @finding.update!(page_member: ask.member, page_email: ask.email, page_integration: ask.integration, page_target: ask.target)

    Investigation::Paging.page!(@investigation.reload)
    Investigation::Paging.page!(@investigation.reload)

    page = @incident.pages.sole
    assert_equal [ Incident::Page::STATE_TRIGGERED, "oncall@acme.io", SystemAgent.investigator ], [ page.state, page.paged_email, page.requested_by ]
    assert_empty @incident.incident_events.where(event_type: IncidentEvent::INCIDENT_ESCALATED)
  end

  test "a page the on-call tool would not take falls back to escalating to the member here, saying why" do
    pagerduty = connect_pagerduty!(@workspace)
    Integrations::PagerdutyApi.any_instance.stubs(:services).returns([])
    @finding.update!(page_member: @bob, page_email: @bob.user.email, page_integration: pagerduty, page_target: "Nowhere")

    Investigation::Paging.page!(@investigation.reload)

    assert_equal Incident::Page::STATE_FAILED, @incident.pages.sole.state
    escalation = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_ESCALATED)
    assert_equal @bob.id, escalation.metadata["escalated_to_member_id"]
    assert_match "PagerDuty has no service called Nowhere.", escalation.metadata["reason"]
  end

  test "with an on-call tool connected a run names what to page there and, when there are several, which tool" do
    connect_pagerduty!(@workspace)
    assert_match "Give target", assert_raises(Investigation::PageRefused) { @investigation.page_to("person" => "oncall@acme.io", "steps" => [ 1 ]) }.message

    connect_opsgenie!(@workspace)
    error = assert_raises(Investigation::PageRefused) { @investigation.page_to("person" => "oncall@acme.io", "steps" => [ 1 ], "target" => "Checkout") }
    assert_equal "Give tool, the on-call tool to page through: pagerduty or opsgenie.", error.message
    assert_equal "opsgenie", @investigation.page_to("person" => "oncall@acme.io", "steps" => [ 1 ], "tool" => "opsgenie", "target" => "team: Platform").integration.slug
  end

  test "someone the facts already name as on call needs no step to show it" do
    @investigation.update!(seed_pack: { Investigation::Seeding::KEY_ON_CALL => { "paging_tools" => [ { "on_call_now" => [ { "email" => @bob.user.email } ] } ] } })

    assert_equal @bob, @investigation.page_to("person" => @bob.user.email.upcase).member
    assert_match "cites no step", assert_raises(Investigation::PageRefused) { @investigation.page_to("person" => "cara@example.com") }.message
  end

  test "conclude hands a refused page back to the agent and records nothing" do
    run = @workspace.investigations.create!(subject: incidents(:active_major_ws1), trigger_source: Investigation::TRIGGER_ALERT, max_turns: 10, max_spend_cents: 400,
                                            critique_asked_at: Time.current)
    run.steps.create!(position: 1, tool_name: "query_metrics", label: "Metrics", action_key: @metrics.action_key,
                      status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)

    answer = Investigation::Tools::Conclude.new(run).call("summary" => "Nothing explains it", "page" => { "person" => "nobody@example.com", "steps" => [ 1 ] })

    assert_match "who is not a member of this workspace", answer[:error]
    assert_nil run.reload.finding
  end
end
