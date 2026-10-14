require "test_helper"

class DefinedWorkflowManualStepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  QUIET = [ WriteSearchEmbeddingJob, SearchDocumentIndexJob, InvestigationJob ].freeze

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
    @adapter.any_instance.stubs(:post_workflow_question_in_channel).returns({ channel_id: @incident.channel_id, message_id: "2.2" })
    @adapter.any_instance.stubs(:update_workflow_question).returns({ success: true })
    stub_successful_slack_workflow
  end

  def step(id, kind, config = {}) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def edge(from, to, route = nil) = { "from" => from, "to" => to, "route" => route }.compact

  def manual(config = {})
    base = { "task" => "Open a ticket with the payment provider.", "to" => "person", "person" => "bob@example.com" }
    workflow = Workflow.create!(workspace: @workspace, name: "Payments", created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    steps = [ step("ticket", "manual", base.merge(config)), step("after", "set_data", { "values" => [ { "name" => "went", "value" => "on" } ] }),
              step("chase", "set_data", { "values" => [ { "name" => "went", "value" => "chase" } ] }) ]
    draft.update!(trigger: { "kind" => "manual", "inputs" => [] }, steps: steps, edges: [ edge("ticket", "after", "done"), edge("ticket", "chase", "not_done") ])
    assert_empty draft.problems
    assert WorkflowPublishService.new(workflow).publish!(draft.reload, by: @alice).ok
    workflow.reload
  end

  def start(workflow, **options)
    run = nil
    perform_enqueued_jobs(except: QUIET) do
      run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, **options)
    end
    run.reload
  end

  def row(run, key) = run.steps.find_by!(step_key: key)

  def task(run) = row(run, "ticket").questions.sole

  test "a task given to a named person reaches them directly, waits, and goes on done with the note they wrote" do
    run = start(manual("note" => "Ticket number"))

    assert_equal Workflow::Run::STATUS_WAITING, run.status, run.error
    given = task(run)
    assert given.task?
    assert_equal [ @bob.id ], given.asked_member_ids
    assert_equal [ { "channel_id" => "D-BOB", "message_id" => "1.1", "member_id" => @bob.id } ], given.notifications

    assert_equal "Only #{@bob.actor_display_name} can mark this done.", WorkflowQuestionService.answer!(given, by: @alice, values: { "note" => "T-1" }).words
    assert_equal "Answer Ticket number.", WorkflowQuestionService.answer!(given, by: @bob, values: { "note" => " " }).words
    perform_enqueued_jobs(except: QUIET) { assert WorkflowQuestionService.answer!(given, by: @bob, values: { "note" => "PAY-412" }).ok }

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal "done", row(run, "ticket").route
    assert_equal({ "done_by" => @bob.actor_display_name, "note" => "PAY-412" }, row(run, "ticket").output)
    assert_equal "succeeded", row(run, "after").status
    assert_equal "bypassed", row(run, "chase").status
  end

  test "a task given to the incident's lead reaches the lead directly" do
    @incident.lead = @bob

    run = start(manual("to" => "lead", "person" => nil, "incident" => @incident.identifier))

    assert_equal [ @bob.id ], task(run).asked_member_ids
  end

  test "a task given to anyone is posted in the incident's channel and anyone in the workspace can mark it done" do
    @adapter.any_instance.expects(:post_workflow_question).never
    @adapter.any_instance.expects(:post_workflow_question_in_channel).once
            .with { |channel_id:, question:| channel_id == @incident.channel_id && question.open_to_anyone? }
            .returns({ channel_id: @incident.channel_id, message_id: "2.2" })

    run = start(manual("to" => "anyone", "person" => nil, "incident" => @incident.identifier))
    given = task(run)
    WorkflowQuestionService.ask!(given.reload)

    assert_empty given.asked_member_ids
    assert_equal [ { "channel_id" => @incident.channel_id, "message_id" => "2.2", "member_id" => nil } ], given.reload.notifications
    perform_enqueued_jobs(except: QUIET) { assert WorkflowQuestionService.answer!(given, by: @alice).ok }
    assert_equal "done", row(run.reload, "ticket").route
    assert_equal({ "done_by" => @alice.actor_display_name }, row(run, "ticket").output)
  end

  test "a task for anyone with no channel anywhere stays on the run's page and says so in the log" do
    @workspace.update!(incidents_channel_id: nil)
    @adapter.any_instance.expects(:post_workflow_question_in_channel).never
    Rails.logger.expects(:warn).with { |line| line.include?("workflow_question.no_channel") }.at_least_once
    Rails.logger.stubs(:warn).with { |line| !line.include?("workflow_question.no_channel") }

    run = start(manual("to" => "anyone", "person" => nil))

    assert task(run).open?
    assert_nil task(run).answer_blocked_reason(@bob)
  end

  test "a task nobody marks done within its wait is withdrawn where it was given and takes its not done route" do
    run = start(manual("wait_minutes" => 45))
    given = task(run)
    @adapter.any_instance.expects(:update_workflow_question).with { |channel_id:, message_id:, question:| channel_id == "D-BOB" && question.expired? }.returns({ success: true })

    travel(46.minutes) { perform_enqueued_jobs(except: QUIET) { SolidWorkflow::SweeperJob.perform_now } }

    run.reload
    assert_equal "not_done", row(run, "ticket").route
    assert_equal({ "done_by" => nil }, row(run, "ticket").output)
    assert_equal "succeeded", row(run, "chase").status
    assert_equal "This task is no longer asked.", WorkflowQuestionService.answer!(given.reload, by: @bob).words
  end

  test "in a test run the person testing can mark the task done" do
    run = start(manual, test: true)

    assert_nil task(run).answer_blocked_reason(@alice)
  end

  test "the message gives the task, a Done button that finishes it in one click, and once done says who did it" do
    run = start(manual)
    given = task(run)
    Slack::DashboardUrl.stubs(:workflow_run).returns("https://firefight.test/halon/workflows/run")

    blocks = Slack::Messages::WorkflowQuestion.build(given)
    assert_equal ":clipboard:  *Payments needs this done*", blocks.first.dig(:text, :text)
    assert_equal "*Open a ticket with the payment provider.*", blocks.third.dig(:text, :text)
    buttons = blocks.find { |block| block[:type] == "actions" }[:elements]
    assert_equal [ [ "Done", Identifiers::WORKFLOW_TASK_DONE, given.id ], [ "Open the run", nil, nil ] ], buttons.map { |button| [ button.dig(:text, :text), button[:action_id], button[:value] ] }
    assert_match "Assigned to <@#{@bob.platform_user_id}>.", blocks.last[:elements].sole[:text]

    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, channel_id: "D-BOB",
                                  user_id: @bob.platform_user_id, action_id: Identifiers::WORKFLOW_TASK_DONE, action_value: given.id)
    perform_enqueued_jobs(except: QUIET) { InteractionDispatcher.dispatch(interaction) }

    assert_equal "done", row(run.reload, "ticket").route
    settled = Slack::Messages::WorkflowQuestion.build(given.reload)
    assert_equal ":clipboard:  *Payments needed this done*", settled.first.dig(:text, :text)
    assert_equal "*#{@bob.actor_display_name}* marked it done.", settled.last[:elements].sole[:text]
  end

  test "a task that collects a note opens a form for it from Done" do
    run = start(manual("note" => "Ticket number"))
    given = task(run)

    button = Slack::Messages::WorkflowQuestion.build(given).find { |block| block[:type] == "actions" }[:elements].first
    assert_equal [ "Done", Identifiers::WORKFLOW_QUESTION_ANSWER ], [ button.dig(:text, :text), button[:action_id] ]
    modal = Slack::Modals::WorkflowQuestionAnswer.build(given)
    assert_equal [ "Done", "Mark done" ], [ modal.dig(:title, :text), modal.dig(:submit, :text) ]
    assert_equal "Ticket number", modal[:blocks].last.dig(:label, :text)
  end

  test "a manual step says what it needs" do
    found = DefinedWorkflow::Steps::Manual.problems(step("x", "manual", { "to" => "lead", "note" => "n" * 80, "wait_minutes" => 1 }), @workspace)

    assert_includes found, "x needs the task it gives."
    assert_includes found, "x needs the incident whose lead it is given to."
    assert_includes found, "x keeps its note's name to 75 characters."
    assert_includes found, "x waits from 5 minutes to 7 days, as a whole number of minutes."
    assert_includes DefinedWorkflow::Steps::Manual.problems(step("x", "manual", { "task" => "Do it", "to" => "someone" }), @workspace),
                    "x needs who it is given to, one of person, lead, anyone."
    assert_includes DefinedWorkflow::Steps::Manual.problems(step("x", "manual", { "task" => "Do it", "to" => "person" }), @workspace),
                    "x needs the person it is given to, by email."
    assert_equal %w[done not_done], Workflow::StepKinds.routes_of(step("x", "manual", {}))
    assert_equal %w[done_by note], Workflow::StepKinds.outputs_of(step("x", "manual", { "note" => "Ticket" }), Workflow::StepKinds::Facts.new)
  end
end
