require "test_helper"

class WorkflowRunAsksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  QUIET = [ WriteSearchEmbeddingJob, SearchDocumentIndexJob, InvestigationJob ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    adapter = WorkspaceAdapter.for(@workspace).class
    adapter.any_instance.stubs(:post_workflow_question).returns({ channel_id: "D-BOB", message_id: "1.1" })
    adapter.any_instance.stubs(:update_workflow_question).returns({ success: true })
    adapter.any_instance.stubs(:post_approval_request).returns({ channel_id: "C-OPS", message_id: "2.2" })
    adapter.any_instance.stubs(:mark_approval_resolved).returns({ success: true })
    stub_successful_slack_workflow
  end

  def run_of(step)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release", created_by: @alice)
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "kind" => "manual", "inputs" => [] }, steps: [ step ], edges: [])
    assert WorkflowPublishService.new(@workflow).publish!(draft.reload, by: @alice).ok
    start
  end

  def start
    run = nil
    perform_enqueued_jobs(except: QUIET) { run = WorkflowRunService.new(@workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }
    run.reload
  end

  test "someone asked answers on the run's page, and anyone else is told who can" do
    run = run_of({ "id" => "ask", "name" => "ask", "kind" => "ask_person",
                   "config" => { "to" => "person", "person" => "bob@example.com", "question" => "Why?", "fields" => [ { "name" => "why", "label" => "Why" } ] } })
    question = run.steps.find_by!(step_key: "ask").questions.sole

    sign_in(users(:alice), @workspace)
    post workflow_run_question_answer_path(@workflow, run, question), params: { values: { why: "Cold cache." } }
    assert_equal "Only #{@bob.actor_display_name} can answer this.", flash[:alert]

    sign_in(users(:bob), @workspace)
    perform_enqueued_jobs(except: QUIET) { post workflow_run_question_answer_path(@workflow, run, question), params: { values: { why: "Cold cache." } } }
    assert_redirected_to workflow_path(@workflow, run: run.id)
    assert_equal "Your answer to Release was sent.", flash[:notice]
    assert_equal "Cold cache.", run.reload.steps.find_by!(step_key: "ask").output["why"]
  end

  test "an approver approves or denies on the run's page, and someone who may not decide is told why" do
    approval_step = { "id" => "approve", "name" => "approve", "kind" => "approval",
                      "config" => { "question" => "Ship?", "who" => "people", "approvers" => [ "alice@example.com" ] } }
    run = run_of(approval_step)
    approval = @workspace.ability_approvals.find_by!(workflow_run_id: run.id)

    sign_in(users(:alice), @workspace)
    perform_enqueued_jobs(except: QUIET) { post workflow_run_approval_approve_path(@workflow, run, approval) }
    assert_redirected_to workflow_path(@workflow, run: run.id)
    assert_equal "You approved Release's request. The run goes on.", flash[:notice]
    assert_equal "approved", run.reload.steps.find_by!(step_key: "approve").route

    again = start
    approval = @workspace.ability_approvals.find_by!(workflow_run_id: again.id)
    perform_enqueued_jobs(except: QUIET) { post workflow_run_approval_deny_path(@workflow, again, approval) }
    assert_equal "You denied Release's request.", flash[:notice]
    assert_equal "denied", again.reload.steps.find_by!(step_key: "approve").route

    post workflow_run_approval_approve_path(@workflow, again, approval)
    assert_equal "Approval is no longer pending.", flash[:alert]
  end

  test "a member the approval names decides it on the run's page without approvals access, and one it does not name is told why" do
    run = run_of({ "id" => "approve", "name" => "approve", "kind" => "approval",
                   "config" => { "question" => "Ship?", "who" => "people", "approvers" => [ "bob@example.com" ] } })
    approval = @workspace.ability_approvals.find_by!(workflow_run_id: run.id)
    assert_nil WorkflowRunDetailSerializer.one_as_hash(run, member: @bob).deep_stringify_keys["steps"].sole.dig("ask", "blockedReason")

    sign_in(users(:bob), @workspace)
    perform_enqueued_jobs(except: QUIET) { post workflow_run_approval_approve_path(@workflow, run, approval) }
    assert_equal "You approved Release's request. The run goes on.", flash[:notice]
    assert_equal "approved", run.reload.steps.find_by!(step_key: "approve").route

    by_role = { "id" => "approve", "name" => "approve", "kind" => "approval", "config" => { "question" => "Ship?", "who" => "role", "role" => "admin" } }
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(steps: [ by_role ])
    assert WorkflowPublishService.new(@workflow).publish!(draft.reload, by: @alice).ok
    again = start
    other = @workspace.ability_approvals.find_by!(workflow_run_id: again.id)
    assert_equal "You don't have permission to decide this request. Ask a workspace admin to grant you approvals access under Gateway, Permissions.",
                 WorkflowRunDetailSerializer.one_as_hash(again, member: @bob).deep_stringify_keys["steps"].sole.dig("ask", "blockedReason")

    post workflow_run_approval_approve_path(@workflow, again, other)
    assert_match "permission", flash[:alert]
    assert other.reload.pending?
  end

  test "the person a task was given to marks it done on the run's page with its note" do
    adapter = WorkspaceAdapter.for(@workspace).class
    adapter.any_instance.stubs(:post_workflow_question_in_channel).returns({ channel_id: "C-OPS", message_id: "3.3" })
    run = run_of({ "id" => "ticket", "name" => "ticket", "kind" => "manual",
                   "config" => { "task" => "Open a ticket.", "to" => "person", "person" => "bob@example.com", "note" => "Ticket number" } })
    given = run.steps.find_by!(step_key: "ticket").questions.sole
    asked = WorkflowRunDetailSerializer.one_as_hash(run, member: @bob).deep_stringify_keys["steps"].sole["ask"]
    assert_equal [ "task", @bob.actor_display_name, [ { "name" => "note", "label" => "Ticket number" } ] ], asked.values_at("kind", "who", "fields")

    sign_in(users(:bob), @workspace)
    perform_enqueued_jobs(except: QUIET) { post workflow_run_question_answer_path(@workflow, run, given), params: { values: { note: "PAY-9" } } }

    assert_equal "You marked Release's task done.", flash[:notice]
    assert_equal({ "done_by" => @bob.actor_display_name, "note" => "PAY-9" }, run.reload.steps.find_by!(step_key: "ticket").output)
  end

  test "the run's page shows what the step asked and whether the person looking may answer it" do
    run = run_of({ "id" => "ask", "name" => "ask", "kind" => "ask_person",
                   "config" => { "to" => "person", "person" => "bob@example.com", "question" => "Ship?", "choices" => %w[ship_it wait] } })

    asked = WorkflowRunDetailSerializer.one_as_hash(run, member: @alice).deep_stringify_keys["steps"].sole["ask"]
    assert_equal "question", asked["kind"]
    assert_equal [ { "value" => "ship_it", "label" => "Ship it" }, { "value" => "wait", "label" => "Wait" } ], asked["choices"]
    assert_equal "Only #{@bob.actor_display_name} can answer this.", asked["blockedReason"]
    assert_nil WorkflowRunDetailSerializer.one_as_hash(run, member: @bob).deep_stringify_keys["steps"].sole["ask"]["blockedReason"]
  end
end
