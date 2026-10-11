require "test_helper"

class OnCallSyncServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include PagingTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @pagerduty = connect_pagerduty!(@workspace)
    @service = OnCallSyncService.new(@workspace)
    IncidentCloseWorkflow.stubs(:start!)
  end

  test "a page is raised on the service through PagerDuty as Firefight paging, and the incident and the activity log say so" do
    Integrations::PagerdutyApi.any_instance.stubs(:services).with(query: "Checkout").returns([ { "id" => "PF9KMXH", "name" => "Checkout" } ])
    Integrations::PagerdutyApi.any_instance.expects(:create_incident).with do |service_id:, title:, details:, incident_key:|
      service_id == "PF9KMXH" && title.start_with?(@incident.identifier) && details == "Checkout returns 500" && incident_key.start_with?(Integrations::Paging::KEY_PREFIX)
    end.returns(pagerduty_incident)

    page = nil
    assert_enqueued_with(job: OnCallApprovalsJob, args: [ @incident.id, @bob.id ]) do
      page = @service.raise_page!(@incident, integration: @pagerduty, target: "Checkout", details: "Checkout returns 500", by: SystemAgent.investigator,
                                             paged_member: @bob, paged_email: "bob@example.com")
    end

    assert_equal [ Incident::Page::STATE_TRIGGERED, "PGR0VU2", "#42", "https://acme.pagerduty.com/incidents/PGR0VU2" ], [ page.state, page.external_id, page.reference, page.url ]
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_RAISED)
    assert_equal [ SystemAgent.investigator, "Checkout through PagerDuty", @bob.id ], [ event.actor, event.subject_label, event.metadata["paged_member_id"] ]
    assert_includes @incident.on_call_members, @bob
    ledger = @workspace.ability_invocations.find_by!(action_key: "pagerduty.manage_incidents")
    assert_equal [ SystemAgent.paging, AbilityGateway::SOURCE_PAGING, Ability::Invocation::OUTCOME_SUCCESS ], [ ledger.principal, ledger.source, ledger.outcome ]
    assert_equal "Firefight Investigator, on a page to Checkout in PagerDuty, for #{@incident.identifier}", ledger.triggered_by_label
  end

  test "a page the tool refuses, or one Firefight paging may no longer raise, fails with why on the incident" do
    Integrations::PagerdutyApi.any_instance.stubs(:service).returns("id" => "PF9KMXH", "name" => "Checkout")
    Integrations::PagerdutyApi.any_instance.stubs(:create_incident).raises(Integrations::PagerdutyApi::Error, "PagerDuty answered 400: Invalid Input Provided")

    page = @service.raise_page!(@incident, integration: @pagerduty, target: "PF9KMXH", details: "Down", by: @alice)

    assert_equal Incident::Page::STATE_FAILED, page.state
    assert_equal "PagerDuty did not raise the incident: PagerDuty answered 400: Invalid Input Provided.", page.sync_note
    failed = @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_FAILED)
    assert_equal [ @alice, "PF9KMXH through PagerDuty" ], [ failed.actor, failed.subject_label ]

    @workspace.ability_grants.where(principal: SystemAgent.paging).destroy_all
    refused = @service.raise_page!(@incident, integration: @pagerduty, target: "PF9KMXH", details: "Down", by: @alice)
    assert_equal Incident::Page::STATE_FAILED, refused.state
    assert_match "Firefight paging may not use pagerduty.browse_services", refused.sync_note
    assert_match "no longer holds", refused.sync_note
  end

  test "a page an approval rule holds waits, is raised once an admin approves it, and says so when declined" do
    AbilityGateway.stubs(:approval_requirement).returns(nil)
    AbilityGateway.stubs(:approval_requirement).with { |_workspace, _action, key, *| key == "pagerduty.manage_incidents" }.returns({ "role" => "admin" })
    Integrations::PagerdutyApi.any_instance.stubs(:service).returns("id" => "PF9KMXH", "name" => "Checkout")
    Integrations::PagerdutyApi.any_instance.stubs(:create_incident).returns(pagerduty_incident)

    page = @service.raise_page!(@incident, integration: @pagerduty, target: "PF9KMXH", details: "Down", by: @alice)

    assert_equal Incident::Page::STATE_AWAITING_APPROVAL, page.state
    assert_equal "Paging PF9KMXH through PagerDuty is waiting for approval.", page.sync_note
    approval = Ability::Approval.find_by!("resume_payload->>'page_id' = ?", page.id)
    assert_equal [ ApprovalResumption::KIND_PAGING, OnCallSyncService::RAISE ], approval.resume_payload.values_at("kind", "operation")

    approval.update!(status: Ability::Approval::STATUS_APPROVED, approver: @alice, resolved_at: Time.current)
    perform_enqueued_jobs(only: OnCallSyncJob) { ApprovalResumption.resume!(approval) }
    assert_equal [ Incident::Page::STATE_TRIGGERED, "PGR0VU2" ], [ page.reload.state, page.external_id ]

    held = @service.raise_page!(incidents(:active_major_ws1), integration: @pagerduty, target: "PF9KMXH", details: "Down", by: @alice)
    denial = Ability::Approval.find_by!("resume_payload->>'page_id' = ?", held.id)
    denial.update!(status: Ability::Approval::STATUS_DENIED, approver: @alice, resolved_at: Time.current)
    ApprovalResumption.decline!(denial)
    assert_equal [ Incident::Page::STATE_FAILED, "#{@alice.actor_display_name} declined it." ], [ held.reload.state, held.sync_note ]
  end

  test "resolving the incident here resolves its open page in PagerDuty, and PagerDuty's echo of that changes nothing" do
    page = triggered_page
    Integrations::PagerdutyApi.any_instance.expects(:update_status).with("PGR0VU2", status: Integrations::PagerdutyApi::STATUS_RESOLVED).returns({})

    perform_enqueued_jobs(only: OnCallSyncJob) do
      IncidentLifecycleService.new(@workspace).change_status(@incident, { incident_status: @workspace.default_closed_status }, changed_by: @alice)
    end

    assert_equal Incident::Page::STATE_RESOLVED, page.reload.state
    ledger = @workspace.ability_invocations.find_by!(action_key: "pagerduty.manage_incidents")
    assert_equal "#{@alice.actor_display_name}, on #42 in PagerDuty, for #{@incident.identifier}", ledger.triggered_by_label

    @service.apply(pagerduty_source!(@workspace), event(Integrations::Paging::EVENT_RESOLVED, by_person: true))
    assert_empty @incident.incident_events.where(event_type: IncidentEvent::PAGE_RESOLVED)
  end

  test "acknowledging an escalation here acknowledges the page there, and the acknowledgement coming back is not recorded twice" do
    page = triggered_page
    escalation = IncidentLifecycleService.new(@workspace).escalate(@incident, escalated_to: @bob, reason: "Need you", changed_by: @alice)
    IncidentUpdateService.any_instance.stubs(:post_escalation_acknowledged_message)
    Integrations::PagerdutyApi.any_instance.expects(:update_status).with("PGR0VU2", status: Integrations::PagerdutyApi::STATUS_ACKNOWLEDGED).returns({})

    perform_enqueued_jobs(only: OnCallSyncJob) do
      assert IncidentLifecycleService.new(@workspace).acknowledge_escalation(@incident, escalation, platform_user_id: @bob.platform_user_id, acknowledged_by: @bob)
    end

    assert_equal Incident::Page::STATE_ACKNOWLEDGED, page.reload.state
    @service.apply(pagerduty_source!(@workspace), event(Integrations::Paging::EVENT_ACKNOWLEDGED))
    assert_empty @incident.incident_events.where(event_type: IncidentEvent::PAGE_ACKNOWLEDGED)
  end

  test "a change PagerDuty did not take is said on the incident, and the page keeps the state Firefight gave it" do
    page = triggered_page
    Integrations::PagerdutyApi.any_instance.stubs(:update_status).raises(Integrations::PagerdutyApi::Error, "PagerDuty answered 403: Access Denied")
    page.move!(from: Incident::Page::STATE_TRIGGERED, to: Incident::Page::STATE_RESOLVED)

    @service.perform(OnCallSyncService::RESOLVE, page, @alice)

    failed = @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_SYNC_FAILED)
    assert_equal "Resolving it there did not happen. PagerDuty did not resolve incident PGR0VU2: PagerDuty answered 403: Access Denied.", failed.metadata["message"]
    assert_equal Incident::Page::STATE_RESOLVED, page.reload.state
  end

  test "someone acknowledging the page in the tool is on the timeline under their name" do
    page = triggered_page

    @service.apply(pagerduty_source!(@workspace), event(Integrations::Paging::EVENT_ACKNOWLEDGED))

    entry = @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_ACKNOWLEDGED)
    assert_equal [ "Ana Diaz", "#42 in PagerDuty", "acknowledged" ], [ entry.actor_name, entry.subject_label, entry.description_stem ]
    assert_not entry.automated?
    assert_equal Incident::Page::STATE_ACKNOWLEDGED, page.reload.state
  end

  test "acknowledging in Opsgenie as a member acknowledges their escalation here too" do
    opsgenie = connect_opsgenie!(@workspace)
    page = @incident.pages.create!(workspace: @workspace, integration: opsgenie, origin: Incident::Page::ORIGIN_RAISED,
                                   state: Incident::Page::STATE_TRIGGERED, external_id: "og-1", target: "team: Platform")
    escalation = IncidentLifecycleService.new(@workspace).escalate(@incident, escalated_to: @bob, reason: "Need you", changed_by: @alice)
    IncidentUpdateService.any_instance.stubs(:post_escalation_acknowledged_message)

    @service.apply(opsgenie_source!(@workspace), Integrations::Paging::Event.new(external_id: "og-1", kind: Integrations::Paging::EVENT_ACKNOWLEDGED,
                                                                               actor_name: "bob@example.com", actor_email: "bob@example.com", by_person: true))

    assert escalation.reload.escalation_acknowledged?
    assert_equal @bob, @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_ACKNOWLEDGED).actor
    assert_no_enqueued_jobs(only: OnCallSyncJob)
    assert_equal Incident::Page::STATE_ACKNOWLEDGED, page.reload.state
  end

  test "an escalation and a note in the tool are recorded once each, however often the tool delivers them" do
    triggered_page
    source = pagerduty_source!(@workspace)
    noted = event(Integrations::Paging::EVENT_NOTED, note: "Rolled back the deploy", id: "delivery-1")

    @service.apply(source, noted)
    @service.apply(source, noted)
    @service.apply(source, event(Integrations::Paging::EVENT_ESCALATED, note: "To Bob Ruiz."))

    note = @incident.incident_events.where(event_type: IncidentEvent::PAGE_NOTED).sole
    assert_equal [ "Rolled back the deploy", "added a note to" ], [ note.metadata["message"], note.description_stem ]
    assert_equal "To Bob Ruiz.", @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_ESCALATED).metadata["message"]
  end

  test "the incident is resolved once a person resolves its last open page in the tool, never when a monitor resolves it" do
    page = triggered_page
    other = @incident.pages.create!(workspace: @workspace, integration: @pagerduty, origin: Incident::Page::ORIGIN_ALERT,
                                    state: Incident::Page::STATE_TRIGGERED, external_id: "PSECOND")
    source = pagerduty_source!(@workspace)

    @service.apply(source, event(Integrations::Paging::EVENT_RESOLVED, by_person: true))
    assert_equal Incident::Page::STATE_RESOLVED, page.reload.state
    assert_not @incident.reload.terminal?

    @service.apply(source, Integrations::Paging::Event.new(external_id: "PSECOND", kind: Integrations::Paging::EVENT_RESOLVED, actor_name: nil, by_person: false))
    assert_equal Incident::Page::STATE_RESOLVED, other.reload.state
    assert_not @incident.reload.terminal?, "a monitor resolving its own incident leaves closing to a person"

    reopened = incidents(:active_major_ws1)
    third = reopened.pages.create!(workspace: @workspace, integration: @pagerduty, origin: Incident::Page::ORIGIN_RAISED,
                                   state: Incident::Page::STATE_ACKNOWLEDGED, external_id: "PTHIRD")
    assert_no_enqueued_jobs(only: OnCallSyncJob) do
      @service.apply(source, Integrations::Paging::Event.new(external_id: "PTHIRD", kind: Integrations::Paging::EVENT_RESOLVED, actor_name: "Ana Diaz", by_person: true))
    end
    assert reopened.reload.closed?
    assert_equal Incident::Page::STATE_RESOLVED, third.reload.state
    assert_equal SystemAgent.paging, reopened.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_RESOLVED).actor
  end

  test "an event about a page Firefight does not know changes nothing" do
    assert_nothing_raised { @service.apply(pagerduty_source!(@workspace), event(Integrations::Paging::EVENT_ACKNOWLEDGED, external_id: "PUNKNOWN")) }
    assert_empty @incident.incident_events.where(event_type: IncidentEvent::PAGE_EVENTS)
  end

  test "a page an alert brought in is kept in step through the one connection to its tool" do
    source = pagerduty_source!(@workspace)
    alert = source.alerts.create!(workspace: @workspace, external_id: "e1", fingerprint: "PADOPTED", status: Alert::STATUS_FIRING,
                                  fields: { "title" => "Checkout failing" }, payload: {}, received_at: Time.current, last_seen_at: Time.current,
                                  incident: @incident)

    page = @service.alert_attached(alert)
    Integrations::PagerdutyApi.any_instance.expects(:update_status).with("PADOPTED", status: Integrations::PagerdutyApi::STATUS_RESOLVED).returns({})
    page.move!(from: Incident::Page::STATE_TRIGGERED, to: Incident::Page::STATE_RESOLVED)
    @service.perform(OnCallSyncService::RESOLVE, page, @alice)

    assert_equal [ Incident::Page::ORIGIN_ALERT, source, @pagerduty ], [ page.origin, page.alert_source, page.reload.integration ]
  end

  private

  def triggered_page
    @incident.pages.create!(workspace: @workspace, integration: @pagerduty, origin: Incident::Page::ORIGIN_RAISED, state: Incident::Page::STATE_TRIGGERED,
                            external_id: "PGR0VU2", reference: "#42", url: "https://acme.pagerduty.com/incidents/PGR0VU2", target: "Checkout")
  end

  def event(kind, external_id: "PGR0VU2", by_person: true, note: nil, id: nil)
    Integrations::Paging::Event.new(id: id, external_id: external_id, kind: kind, actor_name: "Ana Diaz", by_person: by_person, note: note)
  end
end
