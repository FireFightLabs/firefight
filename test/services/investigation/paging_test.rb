require "test_helper"

class Investigation::PagingTest < ActiveSupport::TestCase
  include OnCallTestHelper

  setup do
    alert_run_with_restart_fix
    @workspace.update!(on_call_paging_enabled: true)
    @bob = workspace_memberships(:bob_workspace_one)
    IncidentEscalationWorkflow.stubs(:start!)
  end

  test "a run an alert started names who is on call, and Firefight escalates the incident to them once with what Halon found" do
    page = @investigation.page_to("person" => @bob.user.email, "steps" => [ 1 ])
    @finding.update!(page_member: page)

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
