require "test_helper"

class WorkflowRunsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    @draft = @workflow.open_draft!(by: @alice)
  end

  def step(id, kind, config = {}, **extra) = { "id" => id, "name" => id, "kind" => kind, "config" => config }.merge(extra.stringify_keys)

  def steps!(*steps, edges: [])
    @draft.update!(steps: steps, edges: edges)
    @workflow.reload
  end

  def try!(**options)
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true, **options) }
    run.reload
  end

  test "a member tries the draft, which opens its run on the canvas and says so" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    sign_in(users(:bob), @workspace)

    perform_enqueued_jobs do
      post workflow_test_runs_path(@workflow), params: { inputs: {}, trigger_payload: { "service" => "web" } }, as: :json
    end

    run = @workflow.runs.sole
    assert_redirected_to workflow_path(@workflow, run: run.id)
    assert_equal "Release check is being tried.", flash[:notice]
    assert run.test?
    assert_equal({ "service" => "web" }, run.trigger_payload)
    assert_equal workspace_memberships(:bob_workspace_one), run.started_by
  end

  test "a test run that cannot start says why" do
    steps!(step("pause", "delay", {}))
    sign_in(users(:bob), @workspace)

    post workflow_test_runs_path(@workflow), as: :json

    assert_match "It cannot be tested yet.", flash[:alert]
    assert_empty @workflow.runs
  end

  test "the canvas shows a run with each step's input, output and log, and the newest run's states" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    run = try!
    sign_in(users(:bob), @workspace)

    get workflow_path(@workflow, run: run.id), headers: inertia_headers

    detail = inertia_props["run"]
    assert_equal [ run.id, "succeeded", true ], detail.values_at("id", "status", "test")
    pause = detail["steps"].sole
    assert_equal [ "pause", "succeeded", nil, nil ], pause.values_at("stepKey", "status", "now", "watch")
    assert_equal [ "Started.", "Done." ], pause["log"].map { |entry| entry["text"] }
    assert pause["output"].key?("waited_until")
    assert_not inertia_props["document"]["editable"]

    get workflow_path(@workflow), headers: inertia_headers
    assert_equal run.id, inertia_props["lastRun"]["id"]
    assert_equal [ run.id ], inertia_props["runs"].map { |row| row["id"] }
  end

  test "a step its identity cannot run yet says Needs grant while it is built, never on a run that already happened" do
    steps!(step("look", "call_tool", { "tool" => FirefightTools::SEARCH_INCIDENTS, "arguments" => { "query" => "database" } }))
    run = try!
    sign_in(users(:alice), @workspace)

    get workflow_path(@workflow), headers: inertia_headers
    assert_match "Needs read incidents", inertia_props["document"]["steps"].sole["grantNeeded"]

    get workflow_path(@workflow, run: run.id), headers: inertia_headers
    assert_nil inertia_props["document"]["steps"].sole["grantNeeded"]
  end

  test "a run started by hand says who started it, and one a trigger started does not" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    by_hand = try!(inputs: {})
    triggered = nil
    perform_enqueued_jobs do
      triggered = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, test: true,
                                                           trigger_kind: Workflow::Trigger::KIND_INCIDENT_DECLARED, trigger_payload: { "incident" => { "identifier" => "INC-1" } })
    end
    sign_in(users(:alice), @workspace)

    get workflow_path(@workflow, run: by_hand.id), headers: inertia_headers
    assert_equal "Started by hand by Alice Smith.", inertia_props["run"]["startedLine"]

    get workflow_path(@workflow, run: triggered.id), headers: inertia_headers
    assert_nil inertia_props["run"]["startedLine"]
    assert_equal({ "incident" => { "identifier" => "INC-1" } }, inertia_props["run"]["triggerPayload"])
  end

  test "a run Halon started for someone says so, with what it was given, like a run started by hand" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    for_alice = nil
    for_nobody = nil
    perform_enqueued_jobs do
      for_alice = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_HALON, started_by: @alice, test: true,
                                                           trigger_payload: { "runbook" => { "name" => "Release" } })
      for_nobody = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_HALON, test: true)
    end
    sign_in(users(:alice), @workspace)

    get workflow_path(@workflow, run: for_alice.id), headers: inertia_headers
    assert_equal "Started by Halon for Alice Smith.", inertia_props["run"]["startedLine"]
    assert_equal({ "runbook" => { "name" => "Release" } }, inertia_props["run"]["triggerPayload"])

    get workflow_path(@workflow, run: for_nobody.id), headers: inertia_headers
    assert_equal "Started by Halon.", inertia_props["run"]["startedLine"]
  end

  test "the run shows what it spent on AI and on its sandbox apart, each step's sandbox time, and why a change was skipped" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    run = try!
    Inference.create!(workspace: @workspace, inferable: run, feature: FirefightAi::WorkflowAnswer::FEATURE, provider: "openai", model: "gpt", cost_micros: 120_000, status: "success")
    CodeBox.create!(workspace: @workspace, key: run.code_box_key, provider: Integrations::Sandboxes::Boat::KEY, box_ref: "bx_1", address: "https://box.example.com",
                    secret: "k", last_used_at: Time.current, box_started_at: 1.hour.ago, hourly_micros: 40_000, stopped_at: Time.current, running_seconds: 3600)
    run.steps.sole.update!(sandbox_seconds: 42, sandbox_micros: 467, status: DefinedWorkflow::STEP_SKIPPED,
                           output: { DefinedWorkflow::Steps::Base::OUTPUT_SKIPPED => "Halon checked first and the problem has cleared, so this step did not run." })
    sign_in(users(:bob), @workspace)

    get workflow_path(@workflow, run: run.id), headers: inertia_headers

    detail = inertia_props["run"]
    assert_equal [ 120_000, 40_000 ], detail.values_at("aiSpentMicros", "sandboxSpentMicros")
    assert_equal [ "pause: Halon checked first and the problem has cleared, so this step did not run." ], detail["notes"]
    assert_equal [ 42, 467, "Halon checked first and the problem has cleared, so this step did not run." ], detail["steps"].sole.values_at("sandboxSeconds", "sandboxMicros", "note")
  end

  test "a failed step is tried again, and a waiting step skipped, each saying so" do
    steps!(step("broken", "delay", { "at" => "not a moment" }, retry: { "max_attempts" => 1 }, on_failure: "continue"), step("later", "delay", { "minutes" => 30 }))
    run = try!
    assert_equal "failed", run.steps.find_by!(step_key: "broken").status
    sign_in(users(:bob), @workspace)

    post workflow_run_step_retry_path(@workflow, run, "broken"), params: { iteration: "" }, as: :json
    assert_equal "Broken is being tried again.", flash[:notice]
    assert_redirected_to workflow_path(@workflow, run: run.id)

    post workflow_run_step_skip_path(@workflow, run, "later"), params: { iteration: "" }, as: :json
    assert_equal "Later was skipped, and the rest of the run carries on.", flash[:notice]
  end

  test "a step that has not failed is not tried again" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    run = try!
    sign_in(users(:bob), @workspace)

    post workflow_run_step_retry_path(@workflow, run, "pause"), params: { iteration: "" }, as: :json

    assert_equal "Only a step that failed can be tried again.", flash[:alert]
  end

  test "a run going is stopped and pinned from the canvas, each going back to the run" do
    steps!(step("later", "delay", { "minutes" => 30 }))
    run = try!
    sign_in(users(:alice), @workspace)

    perform_enqueued_jobs { post cancel_workflow_run_path(@workflow, run), as: :json }
    assert_redirected_to workflow_path(@workflow, run: run.id)
    assert_equal "The run of Release check was stopped.", flash[:notice]
    assert_equal Workflow::Run::STATUS_CANCELLED, run.reload.status

    patch pin_workflow_run_path(@workflow, run), as: :json
    assert run.reload.pinned?
  end

  test "a run's own address opens it on the canvas" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    run = try!
    sign_in(users(:bob), @workspace)

    get workflow_run_path(@workflow, run)

    assert_redirected_to workflow_path(@workflow, run: run.id)
  end

  test "a run starts again from a step and opens on the canvas" do
    steps!(step("first", "delay", { "seconds" => 0 }), step("second", "delay", { "seconds" => 0 }), edges: [ { "from" => "first", "to" => "second" } ])
    run = try!
    sign_in(users(:bob), @workspace)

    perform_enqueued_jobs { post workflow_run_rerun_path(@workflow, run), params: { step_key: "second" }, as: :json }

    again = @workflow.runs.find_by!(rerun_of: run)
    assert_redirected_to workflow_path(@workflow, run: again.id)
    assert_equal "Release check started again from Second.", flash[:notice]
    assert again.stood_in?("first")
  end

  test "a step's output is pinned from a run and by hand, and unpinned" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    run = try!
    sign_in(users(:bob), @workspace)

    post workflow_pins_path(@workflow), params: { step_id: "pause", run_id: run.id }, as: :json
    assert_equal "Pause's output is pinned.", flash[:notice]
    assert_equal run.steps.sole.output, @draft.reload.pins.dig("pause", "output")

    post workflow_pins_path(@workflow), params: { step_id: "pause", output: { "waited_until" => "soon" } }, as: :json
    assert_equal({ "waited_until" => "soon" }, @draft.reload.pins.dig("pause", "output"))

    delete workflow_pin_path(@workflow, "pause"), as: :json
    assert_equal "Pause's output is no longer pinned.", flash[:notice]
    assert_empty @draft.reload.pins
  end

  test "a result kept whole is read from the run" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    run = try!
    result = run.saved_results.keep!(tool_name: "search_logs", text: "line one\nline two")
    sign_in(users(:bob), @workspace)

    get workflow_run_saved_result_path(@workflow, run, result)

    assert_equal({ "name" => "search_logs", "text" => "line one\nline two" }, response.parsed_body)
  end
end
