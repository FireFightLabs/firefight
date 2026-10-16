require "test_helper"

class Investigation::RemediationPlanTimelineTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    @workspace = @incident.workspace
    @member = workspace_memberships(:alice_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    finding = @investigation.create_finding!(summary: "The 14:02 deploy halved the pool")
    @plan = Investigation::RemediationPlan.create!(finding: finding, summary: "Put the pool back")
    @pull_request = @plan.steps.create!(position: 1, kind: Investigation::RemediationStep::KIND_PULL_REQUEST, description: "Raise the pool",
                                        title: "Open a pull request with the change", repository: "acme/app")
    @manual = @plan.steps.create!(position: 2, kind: Investigation::RemediationStep::KIND_MANUAL, description: "Tell support",
                                  title: "Tell support")
  end

  test "applying the fix is on the incident's timeline, by whom and with how many steps, and says nothing to webhooks" do
    Webhooks::EventSubscriber.expects(:handle).never

    assert @plan.apply!(by: @member, from: AbilityGateway::SOURCE_WEB)

    applied = @incident.incident_events.find_by!(event_type: IncidentEvent::FIX_APPLIED)
    assert_equal @member, applied.actor
    assert_equal "2 steps. Put the pool back", applied.metadata["message"]
    assert_equal "applied the fix", applied.description
  end

  test "a step that went through says what it produced, with the link split out where the sentence names it" do
    @plan.apply!(by: @member, from: AbilityGateway::SOURCE_WEB)
    @pull_request.update_columns(status: Investigation::RemediationStep::STATUS_RUNNING)

    assert @pull_request.finish!(Investigation::RemediationStep::STATUS_DONE,
                                 result: "Opened https://github.com/FireFightLabs/firefight/pull/856")

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::FIX_STEP_DONE)
    assert_equal "ran step 1 of the fix", event.description
    step = event.fix_step
    assert_equal "Open a pull request with the change", step.title
    assert_equal "Opened a pull request: PR #856", step.result
    assert_equal [ "Opened a pull request: ", "PR #856", "https://github.com/FireFightLabs/firefight/pull/856", "" ],
                 [ step.link.before, step.link.label, step.link.href, step.link.after ]
  end

  test "a step whose outcome already held says so, and a failed one says why" do
    @pull_request.update_columns(status: Investigation::RemediationStep::STATUS_RUNNING)
    @pull_request.finish!(Investigation::RemediationStep::STATUS_DONE, already_done: "Uros Nikolic is already in #inc-003")
    @manual.update_columns(status: Investigation::RemediationStep::STATUS_RUNNING)
    @manual.finish!(Investigation::RemediationStep::STATUS_FAILED, failure: Investigation::RemediationStep::FAILURE_TIMED_OUT)

    done = @incident.incident_events.find_by!(event_type: IncidentEvent::FIX_STEP_DONE)
    assert_equal "Already done: Uros Nikolic is already in #inc-003", done.fix_step.result
    assert_nil done.fix_step.link
    failed = @incident.incident_events.find_by!(event_type: IncidentEvent::FIX_STEP_FAILED)
    assert_equal "could not run step 2 of the fix", failed.description
    assert_equal "Couldn't tell support: the tool didn't answer in time.", failed.fix_step.result
  end

  test "a step a person did is theirs, a cancel names who, and the ending says how many steps went through" do
    @plan.apply!(by: @member, from: AbilityGateway::SOURCE_WEB)
    @manual.mark_done!(by: @member)
    marked = @incident.incident_events.find_by!(event_type: IncidentEvent::FIX_STEP_MARKED_DONE)
    assert_equal [ @member, "marked done step 2 of the fix" ], [ marked.actor, marked.description ]

    @pull_request.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    @plan.settle!
    @plan.record_fix_ended!
    ended = @incident.incident_events.find_by!(event_type: IncidentEvent::FIX_ENDED)
    assert_equal "2 of 2 steps done.", ended.metadata["message"]
  end

  test "cancelling is on the timeline, and an undo once Halon wrote it" do
    @plan.apply!(by: @member, from: AbilityGateway::SOURCE_WEB)
    assert @plan.cancel!(by: @member)
    @plan.record_fix_ended!

    cancelled = @incident.incident_events.find_by!(event_type: IncidentEvent::FIX_CANCELLED)
    assert_equal [ @member, "cancelled the fix" ], [ cancelled.actor, cancelled.description ]
    assert_not @incident.incident_events.exists?(event_type: IncidentEvent::FIX_ENDED)

    undo = Investigation::RemediationPlan.create!(finding: @plan.finding, undoes: @plan, summary: "Put the pool back as it was")
    undo.record_undo_written!
    written = @incident.incident_events.find_by!(event_type: IncidentEvent::FIX_UNDO_WRITTEN)
    assert_equal [ SystemAgent.investigator, "wrote the undo of the fix", true ], [ written.actor, written.description, written.metadata["undo"] ]
  end

  test "a fix on a run with no incident has no timeline to go on" do
    @investigation.update_columns(subject_type: nil, subject_id: nil)
    @plan.reload

    assert_no_difference -> { IncidentEvent.count } do
      @plan.apply!(by: @member, from: AbilityGateway::SOURCE_WEB)
    end
  end
end
