require "test_helper"

class DefinedWorkflowPeopleStepsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    @adapter = WorkspaceAdapter.for(@workspace).class
    @adapter.any_instance.stubs(:post_workflow_failure).returns({})
    @adapter.any_instance.stubs(:post_workflow_question).returns({ channel_id: "D-BOB", message_id: "1.1" })
    @adapter.any_instance.stubs(:update_workflow_question).returns({ success: true })
    @adapter.any_instance.stubs(:post_approval_request).returns({ channel_id: "C-OPS", message_id: "2.2" })
    @adapter.any_instance.stubs(:mark_approval_resolved).returns({ success: true })
    stub_successful_slack_workflow
  end

  QUIET = [ WriteSearchEmbeddingJob, SearchDocumentIndexJob, InvestigationJob ].freeze

  def step(id, kind, config = {}) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def edge(from, to, route = nil) = { "from" => from, "to" => to, "route" => route }.compact

  def published(name, steps:, edges: [])
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "kind" => "manual", "inputs" => [] }, steps: steps, edges: edges)
    assert_empty draft.problems
    result = WorkflowPublishService.new(workflow).publish!(draft.reload, by: @alice)
    assert result.ok, result.words
    workflow.reload
  end

  def start(workflow, **options)
    run = nil
    perform_enqueued_jobs(except: QUIET) do
      run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, **options)
    end
    run.reload
  end

  def sweep(after)
    travel(after) { perform_enqueued_jobs(except: QUIET) { SolidWorkflow::SweeperJob.perform_now } }
  end

  def row(run, key) = run.steps.find_by!(step_key: key)

  test "set data names values for later steps, keeping a lone reference's type and making JSON text an object" do
    values = [ { "name" => "service", "value" => "checkout" }, { "name" => "count", "value" => "{{steps.first.count}}" },
               { "name" => "shaped", "value" => "{\"where\": \"{{steps.first.region}}\"}" } ]
    workflow = published("Shape", steps: [ step("first", "set_data", { "values" => [ { "name" => "count", "value" => "3" }, { "name" => "region", "value" => "eu" } ] }),
                                           step("second", "set_data", { "values" => values }) ], edges: [ edge("first", "second") ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal({ "service" => "checkout", "count" => "3", "shaped" => { "where" => "eu" } }, row(run, "second").output)
  end

  test "set data says what is wrong with its names" do
    problems = DefinedWorkflow::Steps::SetData.problems(step("x", "set_data", { "values" => [ { "name" => "Bad Name", "value" => "1" }, { "name" => "ok", "value" => "1" }, { "name" => "ok", "value" => "2" } ] }), @workspace)

    assert_includes problems, "x needs each value named in lowercase letters, numbers and underscores."
    assert_includes problems, "x names ok more than once."
    assert_includes DefinedWorkflow::Steps::SetData.problems(step("x", "set_data", {}), @workspace), "x needs at least one value to name."
  end

  test "stop ends the run as succeeded, leaving what comes after it, or fails it with its reason" do
    quiet = published("Quiet", steps: [ step("stop", "stop", { "outcome" => "succeeded", "reason" => "Nothing to do" }), step("after", "set_data", { "values" => [ { "name" => "a", "value" => "1" } ] }) ],
                               edges: [ edge("stop", "after") ])
    run = start(quiet)
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal "bypassed", row(run, "after").status

    failing = published("Refuse", steps: [ step("stop", "stop", { "outcome" => "failed", "reason" => "No deploys on Friday" }) ])
    run = start(failing)
    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "No deploys on Friday", run.error
  end

  def ask_bob(config = {})
    base = { "to" => "person", "person" => "bob@example.com", "question" => "Roll back checkout?", "choices" => %w[roll_back wait] }
    ask = step("ask", "ask_person", base.merge(config))
    published("Ask Bob", steps: [ ask, step("back", "set_data", { "values" => [ { "name" => "went", "value" => "back" } ] }),
                                  step("hold", "set_data", { "values" => [ { "name" => "went", "value" => "hold" } ] }) ],
                         edges: [ edge("ask", "back", "roll_back"), edge("ask", "hold", "wait") ])
  end

  test "ask a person asks them in a direct message, waits, and takes the route of the choice they pick" do
    run = start(ask_bob)

    assert_equal Workflow::Run::STATUS_WAITING, run.status, run.error
    question = row(run, "ask").questions.sole
    assert_equal [ @bob.id ], question.asked_member_ids
    assert_equal [ { "channel_id" => "D-BOB", "message_id" => "1.1", "member_id" => @bob.id } ], question.notifications

    refused = WorkflowQuestionService.answer!(question, by: @alice, choice: "roll_back")
    assert_not refused.ok
    assert_equal "Only #{@bob.actor_display_name} can answer this.", refused.words

    answered = nil
    perform_enqueued_jobs(except: QUIET) { answered = WorkflowQuestionService.answer!(question, by: @bob, choice: "roll_back") }
    assert answered.ok

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal({ "answer" => "roll_back", "answered_by" => @bob.actor_display_name }, row(run, "ask").output)
    assert_equal "succeeded", row(run, "back").status
    assert_equal "bypassed", row(run, "hold").status
    assert_equal "#{@bob.actor_display_name} already answered this.", WorkflowQuestionService.answer!(question.reload, by: @bob, choice: "wait").words
  end

  test "ask a person with a short form hands each field on by name" do
    workflow = published("Why", steps: [ step("ask", "ask_person", { "to" => "person", "person" => "bob@example.com", "question" => "Why did it fail?",
                                                                     "fields" => [ { "name" => "reason", "label" => "What went wrong" } ] }) ])
    run = start(workflow)
    question = row(run, "ask").questions.sole

    assert_equal "Answer What went wrong.", WorkflowQuestionService.answer!(question, by: @bob, values: { "reason" => " " }).words
    assert_equal "This question offers no choices.", WorkflowQuestionService.answer!(question, by: @bob, choice: "skip_ahead", values: { "reason" => "Cold." }).words
    perform_enqueued_jobs(except: QUIET) { WorkflowQuestionService.answer!(question, by: @bob, values: { "reason" => "The cache was cold." }) }

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal "answered", row(run, "ask").route
    assert_equal "The cache was cold.", row(run, "ask").output["reason"]
  end

  test "an answer that lands as the time runs out still carries the run its way" do
    run = start(ask_bob)
    question = row(run, "ask").questions.sole
    question.answer!(by: @bob, choice: "wait", values: {})

    sweep(25.hours)

    run.reload
    assert_equal "wait", row(run, "ask").route
    assert_equal({ "answer" => "wait", "answered_by" => @bob.actor_display_name }, row(run, "ask").output)
    assert_equal Workflow::Run::Question::STATUS_ANSWERED, question.reload.status
  end

  test "an answer after the time limit is refused even before the run moves on" do
    run = start(ask_bob)
    question = row(run, "ask").questions.sole

    travel(25.hours) do
      refused = WorkflowQuestionService.answer!(question, by: @bob, choice: "wait")
      assert_equal "This question is no longer asked.", refused.words
      assert_not question.answer!(by: @bob, choice: "wait", values: {})
    end
    assert question.reload.open?
  end

  test "a message sent as the question is settled is redrawn rather than left asking" do
    run = start(ask_bob)
    question = row(run, "ask").questions.sole
    question.update_columns(notifications: [])
    @adapter.any_instance.stubs(:post_workflow_question).with { |**| question.answer!(by: @bob, choice: "wait", values: {}) || true }
            .returns({ channel_id: "D-LATE", message_id: "9.9" })
    @adapter.any_instance.expects(:update_workflow_question).with { |channel_id:, message_id:, question:| channel_id == "D-LATE" && question.answered? }.returns({ success: true })

    WorkflowQuestionService.ask!(question.reload)

    assert_empty question.reload.notifications
  end

  test "a question nobody answers in time is withdrawn and the step takes its unanswered route" do
    run = start(ask_bob)
    question = row(run, "ask").questions.sole

    sweep(25.hours)

    assert_equal Workflow::Run::Question::STATUS_EXPIRED, question.reload.status
    run.reload
    assert_equal "unanswered", row(run, "ask").route
    assert_equal "This question is no longer asked.", WorkflowQuestionService.answer!(question, by: @bob, choice: "wait").words
  end

  test "a question whose run is stopped is withdrawn where it was asked" do
    run = start(ask_bob)
    question = row(run, "ask").questions.sole
    @adapter.any_instance.expects(:update_workflow_question).with { |channel_id:, message_id:, question:| channel_id == "D-BOB" && question.expired? }.returns({ success: true })

    perform_enqueued_jobs(except: QUIET) { run.cancel!(by: @alice) }

    assert_equal Workflow::Run::Question::STATUS_EXPIRED, question.reload.status
  end

  test "in a test run the person testing can answer too" do
    run = start(ask_bob, test: true)
    question = row(run, "ask").questions.sole

    assert_nil question.answer_blocked_reason(@alice)
  end

  test "ask a person says who it cannot find and what its choices and fields need" do
    workflow = published("Nobody", steps: [ step("ask", "ask_person", { "to" => "person", "person" => "nobody@example.com", "question" => "Here?", "choices" => %w[yes no] }) ])
    run = start(workflow)
    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "There is nobody to ask: no member is nobody@example.com.", run.error

    problems = DefinedWorkflow::Steps::AskPerson.problems(step("x", "ask_person", { "to" => "lead", "question" => "Go?", "choices" => [ "Roll back", "unanswered" ],
                                                                                   "fields" => [ { "name" => "answer", "label" => "" } ] }), @workspace)
    assert_includes problems, "x needs the incident whose people it asks."
    assert_includes problems, "x needs each choice named in lowercase letters, numbers and underscores."
    assert_includes problems, "x cannot call a choice unanswered, since that is the route when nobody answers."
    assert_includes problems, "x needs what each field asks."
    assert_includes problems, "x names a field answer or answered_by, which it hands on already."
    assert_includes DefinedWorkflow::Steps::AskPerson.problems(step("x", "ask_person", { "to" => "person", "person" => "a@b.c", "question" => "Go?" }), @workspace),
                    "x needs choices to pick from, a form to fill, or both."
  end

  def approval_flow(config = {})
    base = { "question" => "Release checkout?", "who" => "people", "approvers" => [ "alice@example.com" ] }
    published("Release", steps: [ step("approve", "approval", base.merge(config)),
                                  step("ship", "set_data", { "values" => [ { "name" => "went", "value" => "ship" } ] }),
                                  step("halt", "set_data", { "values" => [ { "name" => "went", "value" => "halt" } ] }),
                                  step("gone", "set_data", { "values" => [ { "name" => "went", "value" => "gone" } ] }) ],
                         edges: [ edge("approve", "ship", "approved"), edge("approve", "halt", "denied"), edge("approve", "gone", "withdrawn") ])
  end

  def requested(run) = @workspace.ability_approvals.find_by!(workflow_run_id: run.id, action_key: Ability::Action::WORKFLOW_APPROVAL)

  test "approval asks its approvers as any approval does, and approved takes the approved route" do
    run = start(approval_flow)

    assert_equal Workflow::Run::STATUS_WAITING, run.status, run.error
    approval = requested(run)
    assert_equal "Release checkout?", approval.question
    assert_equal [ { "kind" => Ability::Principal::KIND_USER, "id" => @alice.id } ], approval.approver_ids
    assert_equal [ { "channel_id" => "C-OPS", "message_id" => "2.2" } ], approval.notifications.first(1)
    assert_equal approval, row(run, "approve").asked_approval
    assert_equal "Only #{@alice.actor_display_name} can decide this request.", approval.decide_blocked_reason(@bob)

    perform_enqueued_jobs(except: QUIET) { approval.approve!(by: @alice) }

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal({ "decision" => "approved", "decided_by" => @alice.actor_display_name, "reason" => nil }, row(run, "approve").output)
    assert_equal "succeeded", row(run, "ship").status
    assert_equal "bypassed", row(run, "halt").status
  end

  test "approval's request in Slack says what the workflow asks rather than an action, and who decides" do
    run = start(approval_flow("details" => "Build 412 passed."))
    approval = requested(run)

    text = Slack::Messages::Approval.build_request(approval)[1].dig(:text, :text)
    assert_equal "*#{approval.principal_label}* asks: *Release checkout?*\n> Build 412 passed.\n*Approvers:* <@#{@alice.platform_user_id}>", text
    assert_equal "Approval required: #{approval.principal_label} asks Release checkout?", Slack::Messages::Approval.request_fallback(approval)
  end

  test "approval denied takes the denied route" do
    run = start(approval_flow("who" => "role", "role" => "admin", "approvers" => []))

    perform_enqueued_jobs(except: QUIET) { requested(run).deny!(by: @alice) }

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal "denied", row(run, "approve").route
    assert_equal "succeeded", row(run, "halt").status
  end

  test "approval is withdrawn once its incident no longer meets its conditions, while it waits" do
    conditions = [ { "field" => "stage", "operator" => "is_one_of", "value" => %w[triage active] } ]
    run = start(approval_flow("incident" => "INC-001", "conditions" => conditions))
    assert_equal Workflow::Run::STATUS_WAITING, run.status, run.error

    IncidentLifecycleService.new(@workspace).change_status(@incident, { incident_status: incident_statuses(:resolved_ws1) }, changed_by: @alice)
    sweep(6.minutes)

    run.reload
    assert_equal "withdrawn", row(run, "approve").route
    assert_equal "INC-001 no longer meets its conditions.", row(run, "approve").output["reason"]
    assert requested(run).expired?
  end

  test "approval approved after its incident moved on is withdrawn rather than carrying on" do
    conditions = [ { "field" => "stage", "operator" => "is_one_of", "value" => %w[triage active] } ]
    run = start(approval_flow("incident" => "INC-001", "conditions" => conditions))
    approval = requested(run)

    IncidentLifecycleService.new(@workspace).change_status(@incident, { incident_status: incident_statuses(:resolved_ws1) }, changed_by: @alice)
    perform_enqueued_jobs(except: QUIET) { approval.approve!(by: @alice) }

    run.reload
    assert_equal "withdrawn", row(run, "approve").route
    assert_match "approved it, but by then INC-001 no longer meets its conditions.", row(run, "approve").output["reason"]
  end

  test "approval nobody decides within its time limit is withdrawn" do
    run = start(approval_flow)

    sweep(25.hours)

    run.reload
    assert_equal "withdrawn", row(run, "approve").route
    assert requested(run).expired?
  end

  test "approval says who decides and what its conditions need" do
    found = DefinedWorkflow::Steps::Approval.problems(step("x", "approval", { "who" => "people", "conditions" => [ { "field" => "stage" } ] }), @workspace)

    assert_includes found, "x needs the question approvers decide."
    assert_includes found, "x needs the people who approve, by email."
    assert_includes found, "x needs the incident its conditions read."
    assert_includes DefinedWorkflow::Steps::Approval.problems(step("x", "approval", { "question" => "Go?", "who" => "role", "role" => "member" }), @workspace),
                    "x needs the role that approves, admin or owner."
  end
end
