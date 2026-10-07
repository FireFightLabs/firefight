require "test_helper"

class InvestigationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include FixPlanTestHelper
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a run on an incident opens over the incident" do
    investigation = investigation_run

    get investigation_url(investigation)

    assert_redirected_to incident_path(@incident, Investigation::QUERY_PARAM => investigation.id)
  end

  test "the incident page draws the run the address asks for, whole" do
    investigation = investigation_run
    invocation = Ability::Invocation.create!(
      workspace: @workspace, principal: SystemAgent.investigator, action_key: "github.fetch_file",
      decision: Ability::Invocation::DECISION_ALLOW, source: AbilityGateway::SOURCE_INVESTIGATION,
      principal_label: SystemAgent.investigator.principal_label, idempotency_key: SecureRandom.uuid
    )
    step = investigation.steps.create!(position: 1, tool_name: "github_fetch_file", label: "Github fetch file billing_controller.rb",
                                       action_key: "github.fetch_file", status: Investigation::Step::STATUS_RUNNING, invocation: invocation)
    step.succeed!(compacted_result: "before_action :require_admin!")
    investigation.record_hypothesis!(assertion: "A missing method", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    investigation.conclude!(summary: "require_admin! is defined nowhere", hypothesis_assertion: "A missing method",
                            evidence: [ { claim: "The controller calls it", steps: [ 1 ] } ],
                            fix: { summary: "Define it", steps: [ { kind: "pull_request", description: "Add require_admin!", repository: "acme/billing" } ] })

    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers

    shown = inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION]
    assert_equal "A missing method", shown.dig("finding", "cause")
    assert_equal [ 1 ], shown.dig("finding", "evidence", 0, "steps")
    assert_equal [ "Define it", "pull_request", "acme/billing" ], [ shown.dig("finding", "fix", "summary"), shown.dig("finding", "fix", "steps", 0, "kind"),
                                                                    shown.dig("finding", "fix", "steps", 0, "repository") ]
    assert_equal 1, shown.dig("hypotheses", 0, "settledAfterStep")
    assert_equal "before_action :require_admin!", shown.dig("steps", 0, "result")
    assert_equal Ability::Invocation::DECISION_ALLOW, shown.dig("steps", 0, "receipt", "decision")
  end

  test "the story is handed each time the run made room, and never the note it wrote itself" do
    investigation = investigation_run
    chat = investigation.chat_record
    compaction = chat.compactions.create!(stage: Chat::Compaction::STAGE_CLEARED, tokens_before: 90_000, tokens_freed: 20_000, note: "The pool config looks guilty")

    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers

    shown = inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION]["compactions"]
    assert_equal [ [ compaction.step_key, Chat::Compaction::SHOWN_AS ] ], shown.map { |each| [ each["key"], each["title"] ] }
    assert_no_match "pool config", response.body
  end

  test "a technical cause is never shown, only the plain sentence the thread was told" do
    investigation = investigation_run(status: Investigation::STATUS_FAILED, error_summary: "Faraday::TimeoutError")

    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers

    assert_equal Investigation::GAVE_UP, inertia_props.dig(IncidentsController::PROP_OPEN_INVESTIGATION, "stoppedBecause")
  end

  test "a run on another incident opens nothing" do
    other = investigation_run(subject: incidents(:active_major_ws1))

    get incident_url(@incident, Investigation::QUERY_PARAM => other.id), headers: inertia_headers

    assert_nil inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION]
  end

  test "a run asked without an incident is shown on its own" do
    question = investigation_run(subject: nil, brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" })

    get investigation_url(question), headers: inertia_headers

    assert_equal "checkout is slow", inertia_props.dig(InvestigationsController::PROP_INVESTIGATION, "question")
  end

  test "a rehearsal cannot be opened" do
    rehearsal = investigation_run(rehearsal: true, trigger_source: Investigation::TRIGGER_REHEARSAL)

    get investigation_url(rehearsal), headers: inertia_headers

    assert_response :not_found
  end

  test "a responder adds a note to a running run, which the story shows until and after the run reads it" do
    investigation = investigation_run(status: Investigation::STATUS_RUNNING)

    post investigation_notes_url(investigation), params: { note: "  skip GitHub, look at 5xx on web  " }

    assert_equal Investigation::Noting::NOTE_ADDED, flash[:notice]
    note = investigation.notes.sole
    assert_equal "skip GitHub, look at 5xx on web", note.content
    assert_equal workspace_memberships(:alice_workspace_one), note.sender

    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers

    shown = inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION]["notes"].sole
    assert_equal "skip GitHub, look at 5xx on web", shown["content"]
    assert_nil shown["takenAt"]
  end

  test "a member steers a run without any grant, and one an admin took it away from is refused with the usual sentence" do
    bob = workspace_memberships(:bob_workspace_one)
    sign_in(users(:bob), @workspace)
    investigation = investigation_run(status: Investigation::STATUS_RUNNING)

    post investigation_notes_url(investigation), params: { note: "look at 5xx on web" }
    assert_equal bob, investigation.notes.sole.sender

    take_halon_from(@workspace, bob)
    post investigation_notes_url(investigation), params: { note: "and the queue" }
    post investigation_stop_url(investigation)

    assert_equal WebAuthorization.denied_message(AbilityGateway::Denied.new(Ability::Action::INVESTIGATIONS_CREATE)), flash[:alert]
    assert_equal 1, investigation.notes.count
    assert_not investigation.reload.cancel_requested?
  end

  test "the Investigate button starts a run as the person, says so, and opens the run over the incident" do
    sign_in(users(:bob), @workspace)

    assert_enqueued_with(job: InvestigationJob) do
      post incident_investigations_url(@incident)
    end

    started = @incident.investigations.sole
    assert_equal [ Investigation::TRIGGER_DASHBOARD, workspace_memberships(:bob_workspace_one) ], [ started.trigger_source, started.triggered_by ]
    assert_redirected_to incident_path(@incident, Investigation::QUERY_PARAM => started.id)
    assert_equal "Halon is investigating #{@incident.identifier}.", flash[:notice]
  end

  test "the incident page offers the button, disabled and pointing at the run while one works" do
    get incident_url(@incident), headers: inertia_headers
    assert_equal({ "blockedReason" => nil, "runningHref" => nil }, inertia_props[IncidentsController::PROP_INVESTIGATION_START])

    running = investigation_run(status: Investigation::STATUS_RUNNING)
    get incident_url(@incident), headers: inertia_headers

    assert_equal "Halon is already investigating #{@incident.identifier}.", inertia_props[IncidentsController::PROP_INVESTIGATION_START]["blockedReason"]
    assert_equal incident_path(@incident, Investigation::QUERY_PARAM => running.id), inertia_props[IncidentsController::PROP_INVESTIGATION_START]["runningHref"]

    assert_no_difference -> { @incident.investigations.count } do
      post incident_investigations_url(@incident)
    end
    assert_equal "Halon is already investigating #{@incident.identifier}.", flash[:alert]
  end

  test "a closed incident's button says why, and a workspace without Halon or a member without the grant gets none" do
    closed = incidents(:resolved_minor_ws1)
    get incident_url(closed), headers: inertia_headers
    assert_equal closed.investigation_blocked_reason, inertia_props[IncidentsController::PROP_INVESTIGATION_START]["blockedReason"]

    take_halon_from(@workspace, workspace_memberships(:bob_workspace_one))
    sign_in(users(:bob), @workspace)
    get incident_url(@incident), headers: inertia_headers
    assert_nil inertia_props[IncidentsController::PROP_INVESTIGATION_START]
    post incident_investigations_url(@incident)
    assert_not @incident.investigations.exists?

    sign_in(users(:alice), @workspace)
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)
    get incident_url(@incident), headers: inertia_headers
    assert_nil inertia_props[IncidentsController::PROP_INVESTIGATION_START]
  end

  test "an answer is rated partly right from the run page, counted as Slack's rating is, and the page shows the person's own" do
    investigation = investigation_run
    finding = investigation.conclude!(summary: "The 14:02 deploy did it")
    sign_in(users(:bob), @workspace)

    post investigation_rating_url(investigation), params: { outcome: Investigation::Finding::OUTCOME_PARTIAL }

    assert_equal "Thanks. You rated this answer partly right.", flash[:notice]
    verdict = finding.verdicts.sole
    assert_equal [ Investigation::Finding::OUTCOME_PARTIAL, workspace_memberships(:bob_workspace_one) ], [ verdict.outcome, verdict.member ]
    assert_equal 1, Investigation::Performance.new(@workspace, days: 30).verdicts[Investigation::Finding::OUTCOME_PARTIAL]

    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers
    assert_equal Investigation::Finding::OUTCOME_PARTIAL, inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION].dig("finding", "myVerdict")

    sign_in(users(:alice), @workspace)
    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers
    assert_nil inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION].dig("finding", "myVerdict")
  end

  test "a rating needs an answer and one of the three outcomes" do
    investigation = investigation_run

    post investigation_rating_url(investigation), params: { outcome: Investigation::Finding::OUTCOME_CONFIRMED }
    assert_response :not_found

    investigation.conclude!(summary: "The 14:02 deploy did it")
    post investigation_rating_url(investigation), params: { outcome: "sort of" }
    assert_response :not_found
    assert_not Investigation::Verdict.exists?
  end

  test "a note's files open from the story for whoever reads the run, an image shown and any other file downloaded" do
    investigation = investigation_run(status: Investigation::STATUS_RUNNING)
    image = note_file(investigation, "halon_graph.png", file_fixture("halon_graph.png").binread)
    log = note_file(investigation, "page.html", "<script>alert(1)</script>")
    sign_in(users(:bob), @workspace)

    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers
    shown = inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION]["notes"].flat_map { |note| note["files"] }
    assert_equal [ investigation_file_path(investigation, image), investigation_file_path(investigation, log) ], shown.map { |file| file["url"] }

    get investigation_file_url(investigation, image)
    assert_response :success
    assert_equal file_fixture("halon_graph.png").binread, response.body
    assert_equal "image/png", response.media_type
    assert_match "inline", response.headers["Content-Disposition"]
    assert_match "sandbox", response.headers["Content-Security-Policy"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    get investigation_file_url(investigation, log)
    assert_equal "text/plain", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]
  end

  test "a file opens only through the run it went with, and never for a rehearsal or a file Halon did not read" do
    investigation = investigation_run(status: Investigation::STATUS_RUNNING)
    other = investigation_run(subject: incidents(:active_major_ws1), status: Investigation::STATUS_RUNNING)
    file = note_file(investigation, "a.log", "a")
    unread = Chat::Attachment.unread!(workspace: @workspace, uploaded_by: workspace_memberships(:alice_workspace_one),
                                      filename: "huge.bin", byte_size: 99, refusal: "Too large")
    investigation.add_note!("", by: workspace_memberships(:alice_workspace_one), files: [ unread ])

    get investigation_file_url(other, file)
    assert_response :not_found

    get investigation_file_url(investigation, unread)
    assert_response :not_found

    investigation.update_columns(rehearsal: true)
    get investigation_file_url(investigation, file)
    assert_response :not_found
  end

  test "a finished run takes no note, and says why" do
    investigation = investigation_run

    post investigation_notes_url(investigation), params: { note: "skip GitHub" }

    assert_equal Investigation::Noting::NOTE_AFTER_THE_END, flash[:alert]
    assert_empty investigation.notes
  end

  test "an empty note is refused" do
    investigation = investigation_run(status: Investigation::STATUS_RUNNING)

    post investigation_notes_url(investigation), params: { note: "   " }

    assert_equal Investigation::Noting::NOTE_EMPTY, flash[:alert]
  end

  test "a running run is stopped from the dashboard, and a finished one says it already finished" do
    running = investigation_run(status: Investigation::STATUS_RUNNING)

    post investigation_stop_url(running)

    assert running.reload.cancel_requested?
    assert_equal Investigation::STOPPING, flash[:notice]

    post investigation_stop_url(investigation_run(subject: nil, brief: { Investigation::Brief::KEY_SYMPTOM => "slow" }))

    assert_equal Investigation::ALREADY_FINISHED, flash[:alert]
  end

  test "a fix is applied from the run page as whoever clicked, and a second click is told who got there first" do
    plan = build_fix_plan(@workspace)
    investigation = plan.finding.investigation

    assert_enqueued_with(job: InvestigationFixJob, args: [ plan.id ]) { post investigation_fix_url(investigation) }

    assert_equal Investigation::FixRunner::APPLYING, flash[:notice]
    assert_equal [ workspace_memberships(:alice_workspace_one), AbilityGateway::SOURCE_WEB ], [ plan.reload.approved_by, plan.applied_from ]
    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers
    fix = inertia_props.dig(IncidentsController::PROP_OPEN_INVESTIGATION, "finding", "fix")
    assert_equal [ "applying", "Alice Smith", "Alice Smith already applied this fix." ], [ fix["status"], fix["appliedBy"], fix["applyBlockedReason"] ]

    post investigation_fix_url(investigation)
    assert_equal "Alice Smith already applied this fix.", flash[:alert]
  end

  test "a person's step is marked done from the run page, one waiting on another is not yet, and a step Firefight runs is not" do
    plan = build_fix_plan(@workspace)
    investigation = plan.finding.investigation

    post investigation_fix_step_done_url(investigation, plan.steps.third)
    assert_equal Investigation::FixRunner::MARKED_DONE, flash[:notice]
    assert_equal Investigation::RemediationStep::STATUS_DONE, plan.steps.third.reload.status

    post investigation_fix_step_done_url(investigation, plan.steps.second)
    assert_equal "Step 2 waits on step 1, which is not done yet.", flash[:alert]

    post investigation_fix_step_done_url(investigation, plan.steps.first)
    assert_equal "Firefight runs step 1 itself once the fix is applied.", flash[:alert]
  end

  test "an approved step is run from the run page once, with what the page shows about it, and a second press is refused" do
    plan = build_fix_plan(@workspace)
    alice = workspace_memberships(:alice_workspace_one)
    plan.apply!(by: alice, from: AbilityGateway::SOURCE_WEB)
    investigation = plan.finding.investigation
    approval = @workspace.ability_approvals.create!(principal: alice, principal_label: "user:Alice Smith", action_key: "cloudflare.execute",
                                                    request_digest: "d", required_role: "admin", status: Ability::Approval::STATUS_APPROVED,
                                                    approver: alice, held_for_run: true, run_expires_at: 52.minutes.from_now)
    step = plan.steps.first
    step.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED, approval_id: approval.id, checked_state: "The rule is still there.",
                        state_change: Chat::CurrentState::UNCHANGED, state_checked_at: Time.current)

    Current.principal = workspace_memberships(:bob_workspace_one)
    shown = InvestigationRemediationStepSerializer.one_as_hash(step.reload).stringify_keys
    assert_equal [ "Alice Smith", "The rule is still there.", [ "run", "dismiss" ] ], shown.values_at("approvedBy", "state", "offers")
    assert_match "Only Alice Smith or someone who may run cloudflare_execute", shown["runBlockedReason"]
    Current.reset

    assert_enqueued_with(job: InvestigationFixJob, args: [ plan.id, step.id, approval.id ]) { post investigation_fix_step_run_url(investigation, step) }
    assert_equal "Running the step now.", flash[:notice]
    post investigation_fix_step_run_url(investigation, step)
    assert_equal "Step 1 is running.", flash[:alert]
  end

  test "an applied fix's undo is asked for from the run page, shown under the fix, and applied by its own address" do
    plan = build_fix_plan(@workspace)
    plan.update_columns(status: Investigation::RemediationPlan::STATUS_APPLIED)
    plan.steps.update_all(status: Investigation::RemediationStep::STATUS_DONE)
    FirefightAi.stubs(:context_window).returns(200_000)
    investigation = plan.finding.investigation

    assert_enqueued_with(job: InvestigationUndoJob) { post investigation_fix_undo_url(investigation) }
    assert_equal Investigation::UndoWriter::WRITING, flash[:notice]

    undo = plan.propose_undo!("summary" => "Put it back", "verify" => "Rule is listed again",
                              "steps" => [ { "kind" => "action", "description" => "Recreate", "tool" => "cloudflare_execute" } ])
    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers
    shown = inertia_props.dig(IncidentsController::PROP_OPEN_INVESTIGATION, "finding", "fix")
    assert_equal [ "Put it back", "This is already the undo of a fix." ], [ shown.dig("undo", "summary"), shown.dig("undo", "undoBlockedReason") ]
    assert_equal [ "Remove the rule", nil, "Rule is listed again" ], [ shown["summary"], shown["verify"], shown.dig("undo", "verify") ],
                 "the undo never writes over the fix it is nested in"
    assert_equal [ false, true ], [ shown["isUndo"], shown.dig("undo", "isUndo") ]
    assert_equal JSON.pretty_generate("code" => "delete"), shown.dig("steps", 0, "arguments"), "a tool step shows what it sends before anyone applies it"

    assert_enqueued_with(job: InvestigationFixJob, args: [ undo.id ]) { post investigation_fix_url(investigation), params: { plan_id: undo.id } }
    assert_equal Investigation::RemediationPlan::STATUS_APPLYING, undo.reload.status
  end

  test "a fix being applied is cancelled from the run page, and says who stopped it" do
    plan = build_fix_plan(@workspace)
    plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_WEB)
    investigation = plan.finding.investigation

    post investigation_fix_cancel_url(investigation), params: { plan_id: plan.id }

    assert_equal Investigation::FixRunner::CANCELLED, flash[:notice]
    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers
    fix = inertia_props.dig(IncidentsController::PROP_OPEN_INVESTIGATION, "finding", "fix")
    assert_equal [ "cancelled", "Alice Smith", "Only a fix being applied can be cancelled." ], [ fix["status"], fix["cancelledBy"], fix["cancelBlockedReason"] ]
  end

  private

  def note_file(investigation, name, bytes)
    file = Chat::Attachment.take!(workspace: @workspace, uploaded_by: workspace_memberships(:alice_workspace_one), filename: name, bytes: bytes)
    investigation.add_note!("", by: workspace_memberships(:alice_workspace_one), files: [ file ])
    file
  end

  def investigation_run(**attributes)
    @workspace.investigations.create!(
      { subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
        max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED }.merge(attributes)
    )
  end
end
