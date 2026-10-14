require "test_helper"

class DefinedWorkflowStepsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_failure).returns({})
  end

  def step(id, kind, config = {}, **extra) = { "id" => id, "name" => id, "kind" => kind, "config" => config }.merge(extra.stringify_keys)

  def edge(from, to, route = nil) = { "from" => from, "to" => to, "route" => route }.compact

  def published(name, steps:, edges: [], trigger: { "kind" => "manual", "inputs" => [] }, grant: true)
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(trigger: trigger, steps: steps, edges: edges)
    assert_empty draft.problems
    result = WorkflowPublishService.new(workflow).publish!(draft.reload, by: grant ? @alice : nil)
    assert result.ok, result.words
    workflow.reload
  end

  def start(workflow, **options)
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, **options) }
    run.reload
  end

  def refusal(workflow, **options)
    assert_raises(Workflow::Run::Refused) do
      WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, **options)
    end.message
  end

  # A restart of web, which changes something, with a read after it as its check.
  def restart_then_check(name)
    restart = step("restart", "call_tool", { "tool" => "restart", "arguments" => { "resource" => "web" }, "undo" => "Roll web back to the deploy before." })
    published(name, steps: [ restart, search ], edges: [ edge("restart", "look") ])
  end

  def search = step("look", "call_tool", { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => { "query" => "database" } })

  test "a tool step calls the tool as the workflow's own identity" do
    workflow = published("Look around", steps: [ search ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    output = run.steps.find_by!(step_key: "look").output
    assert output["answer"].present?
    assert_kind_of Hash, output["data"]
    assert_equal workflow.agent, run.agent
  end

  test "a change is in the activity log with the workflow as its source, naming the run" do
    workflow = published("Tell", steps: [ step("tell", "post_to_channel", { "channel" => "#ops", "message" => "Hello" }) ])
    ChannelPostService.any_instance.stubs(:post!).returns(ChannelPostService::Posted.new(channel_id: "C1", channel_name: "ops", link: nil))

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    invocation = run.invocations.sole
    assert_equal AbilityGateway::SOURCE_WORKFLOW, invocation.source
    assert_equal workflow.agent, invocation.principal
    assert_equal run.ledger_label, invocation.triggered_by_label
    assert_equal [ invocation ], run.steps.find_by!(step_key: "tell").invocations.to_a
  end

  test "publishing grants the identity exactly what its steps read, and nothing reaches a tool it was not granted" do
    workflow = published("Look around", steps: [ search ])
    assert_equal [ "incidents.read" ], workflow.agent.ability_grants.map { |grant| grant.action.key }

    workflow.agent.ability_grants.destroy_all
    run = start(workflow)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "may not use search_incidents", run.error
    assert_match "An admin grants it on the workflow's page", run.error
  end

  test "following one of Firefight's skills needs only what its tools read, never what they change" do
    skill = Struct.new(:source, :tools).new(Chat::Skill::SOURCE_FIREFIGHT, [ Mcp::Tools::SEARCH_INCIDENTS, Mcp::Tools::DECLARE_INCIDENT ])

    keys = DefinedWorkflow::Reach.for_skill(@workspace, skill).map(&:key)

    assert_includes keys, Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)
    assert_not_includes keys, Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_CREATE)
  end

  test "a change in a test run is shown and not made, unless the tester turned it on" do
    post = step("tell", "post_to_channel", { "channel" => "#ops", "message" => "Hello" })
    workflow = published("Tell", steps: [ post ])
    ChannelPostService.any_instance.expects(:post!).never

    run = start(workflow, test: true)

    assert run.test?
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal true, run.steps.find_by!(step_key: "tell").output["simulated"]

    ChannelPostService.any_instance.unstub(:post!)
    ChannelPostService.any_instance.expects(:post!).with(has_entries(channel: "#ops", message: "Hello", by: @alice))
                      .returns(ChannelPostService::Posted.new(channel_id: "C1", channel_name: "ops", link: "https://slack/p1"))
    real = start(workflow, test: true, real_step_keys: [ "tell" ])
    assert_equal Workflow::Run::STATUS_SUCCEEDED, real.status, real.error
    assert_equal "#ops", real.steps.find_by!(step_key: "tell").output["channel"]
  end

  test "a held change parks the run until someone approves it, then runs exactly that call" do
    post = step("tell", "post_to_channel", { "channel" => "#ops", "message" => "Hello" })
    workflow = published("Tell", steps: [ post ])
    PolicyRule::ApprovalConditions.stubs(:errors_for).returns([])
    AbilityGateway.stubs(:approval_requirement).returns({ "role" => "admin", "count" => 1 })
    ChannelPostService.any_instance.stubs(:post!).returns(ChannelPostService::Posted.new(channel_id: "C1", channel_name: "ops", link: nil))

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_WAITING, run.status
    approval = Ability::Approval.find_by!(workflow_run_id: run.id)
    assert_equal Ability::Action::CHANNEL_POST, approval.action_key

    AbilityGateway.unstub(:approval_requirement)
    perform_enqueued_jobs { approval.approve!(by: @alice) }

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.reload.status, run.error
  end

  test "a held change nobody decides in time is withdrawn, and where it was asked says why" do
    post = step("tell", "post_to_channel", { "channel" => "#ops", "message" => "Hello" }, timeout_seconds: 600)
    workflow = published("Tell", steps: [ post ])
    PolicyRule::ApprovalConditions.stubs(:errors_for).returns([])
    AbilityGateway.stubs(:approval_requirement).returns({ "role" => "admin", "count" => 1 })
    run = start(workflow)
    approval = Ability::Approval.find_by!(workflow_run_id: run.id)
    approval.update_columns(notifications: [ { "channel_id" => "C-OPS", "message_id" => "7.7" } ])
    WorkspaceAdapter.for(@workspace).class.any_instance.expects(:mark_approval_resolved)
                    .with { |approval:, channel_id:, message_id:| channel_id == "C-OPS" && approval.withdrawn_reason == "Nobody decided within 10 minutes, so it did not run." }
                    .returns({ success: true })

    travel(11.minutes) { perform_enqueued_jobs { SolidWorkflow::SweeperJob.perform_now } }

    assert approval.reload.expired?
    assert_equal Workflow::Run::STATUS_FAILED, run.reload.status
  end

  test "a denied change fails the step, and an error route carries the run on" do
    post = step("tell", "post_to_channel", { "channel" => "#ops", "message" => "Hello" }, on_failure: "error_route")
    workflow = published("Tell", steps: [ post, step("after", "delay", { "seconds" => 0 }) ], edges: [ edge("tell", "after", "error") ])
    AbilityGateway.stubs(:approval_requirement).returns({ "role" => "admin", "count" => 1 })

    run = start(workflow)
    approval = Ability::Approval.find_by!(workflow_run_id: run.id)
    AbilityGateway.unstub(:approval_requirement)
    perform_enqueued_jobs { approval.deny!(by: @alice) }

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status
    assert_match "declined", run.steps.find_by!(step_key: "tell").error
    assert_equal "succeeded", run.steps.find_by!(step_key: "after").status
  end

  test "a change inside a freeze window stops the run, or waits it out when the workflow says so" do
    window = Workspace::FreezeWindows::Window.new(name: "Launch", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    Workspace::FreezeWindows.stubs(:covering).returns(window)
    workflow = restart_then_check("Restart")

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "Changes are frozen for Launch", run.error

    workflow.update!(freeze_behaviour: Workflow::FREEZE_WAIT)
    waiting = start(workflow)
    assert_equal Workflow::Run::STATUS_WAITING, waiting.status
  end

  test "a scheduled change reads how things stand first and stops when they moved" do
    workflow = restart_then_check("Nightly restart")
    Chat::StateCheck.expects(:run).returns(Chat::CurrentState::Report.new(state: "web was restarted 2 minutes ago.", change: Chat::CurrentState::DONE_ALREADY))

    run = start(workflow, trigger_kind: Workflow::Trigger::KIND_SCHEDULE, started_by_kind: Workflow::Run::STARTED_BY_TRIGGER)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "This looks done already. web was restarted 2 minutes ago. Nothing ran.", run.error
  end

  # A step of a run parked on Halon, with the engine's own step, for handing off more work by hand.
  def parked_on_halon
    workflow = published("Judge", steps: [ step("judge", "ask_halon", { "question" => "Is web fine?", "data" => "ok" }) ])
    run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice)
    perform_enqueued_jobs(except: WorkflowHalonStepJob)
    engine = SolidWorkflow::Workflow.find_by!(start_key: DefinedWorkflow.start_key_for(run))
    [ run.reload, engine.steps.find_by!(name: "judge") ]
  end

  test "work handed off late in a step's life gets its own full wait, counted from when it was handed off" do
    run, engine_step = parked_on_halon
    handed = []

    travel 2.hours do
      parked = DefinedWorkflow::Steps::Base.new(run: run, step: engine_step, config: {}).send(:await, "state_check:later") { |name| handed << name }

      assert_kind_of SolidWorkflow::Park, parked
      assert_in_delta 30.minutes.from_now, parked.wake_at, 5
    end
    assert_equal [ "state_check:later" ], handed
  end

  test "a retried step hands its work off again rather than reading what the try before it got back" do
    run, engine_step = parked_on_halon
    DefinedWorkflow.deliver!(engine_step.id, DefinedWorkflow::Steps::AskHalon::HANDED_OFF, { Workflow::HalonStep::KEY_ERROR => "The model was busy." })
    engine_step.workflow.record_event(SolidWorkflow::Events::Step::RETRY_SCHEDULED, step: engine_step.reload, delay: 0, attempt: 1)
    handed = []

    answer = DefinedWorkflow::Steps::Base.new(run: run, step: engine_step, config: {}).send(:await, DefinedWorkflow::Steps::AskHalon::HANDED_OFF) { |name| handed << name }

    assert_kind_of SolidWorkflow::Park, answer
    assert_equal 1, handed.size
    assert_not_equal DefinedWorkflow::Steps::AskHalon::HANDED_OFF, handed.sole
  end

  test "ask halon answers as fields a branch can read" do
    answer = FirefightAi::WorkflowAnswer::Answer.new(verdict: "problem", summary: "Errors doubled.", fields: { "worst" => "checkout" })
    FirefightAi::WorkflowAnswer.any_instance.expects(:answer).with(has_entries(question: "Is it fine?", fields: [ [ "worst", "The worst service" ] ])).returns(answer)
    Investigation.stubs(:unavailable_reason).returns(nil)
    judge = step("judge", "ask_halon", { "question" => "Is it fine?", "data" => { "rate" => 3 }, "fields" => [ { "name" => "worst", "description" => "The worst service" } ] })
    decide = step("decide", "branch", { "routes" => [ { "route" => "bad", "when" => { "left" => "{{steps.judge.verdict}}", "operator" => "equals", "right" => "problem" } } ],
                                        "otherwise" => "fine" })
    workflow = published("Judge", steps: [ judge, decide ], edges: [ edge("judge", "decide") ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal({ "verdict" => "problem", "summary" => "Errors doubled.", "worst" => "checkout" }, run.steps.find_by!(step_key: "judge").output)
    assert_equal "bad", run.steps.find_by!(step_key: "decide").route
  end

  test "a halon step past the run's AI ceiling fails without calling the model" do
    Investigation.stubs(:unavailable_reason).returns(nil)
    FirefightAi::WorkflowAnswer.any_instance.expects(:answer).never
    workflow = published("Judge", steps: [ step("judge", "ask_halon", { "question" => "Is it fine?", "data" => "x" }) ])
    workflow.update!(cost_cap_cents: 5)
    Workflow::Run.any_instance.stubs(:ai_spent_cents).returns(5)

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "spent its AI ceiling", run.error
  end

  test "a raised notice is said once in the monitoring channel, and again only when it got worse" do
    @workspace.update!(halon_monitoring_channel: "C0MONITOR")
    notice = step("raise", "raise_notice", { "signal" => "probing", "topic" => "Probing of shop", "summary" => "Scanners walked /wp-admin.", "severity" => "medium" })
    workflow = published("Probe", steps: [ notice ])
    WorkspaceAdapter.for(@workspace).class.any_instance.expects(:post_monitoring_notice).once.returns({ channel_id: "C0MONITOR", message_id: "1.2" })

    first = start(workflow)
    second = start(workflow)

    assert_equal true, first.steps.find_by!(step_key: "raise").output["said"]
    assert_equal false, second.steps.find_by!(step_key: "raise").output["raised"]
    assert_equal second, @workspace.investigation_notices.find_by!(topic: "Probing of shop").workflow_run
  end

  test "a notice about a resource not on the map is still raised and said, naming the resource in words" do
    @workspace.update!(halon_monitoring_channel: "C0MONITOR")
    notice = step("raise", "raise_notice", { "signal" => "disk", "topic" => "Disk of reports-db", "summary" => "Fills in a week.", "severity" => "medium",
                                              "resource" => "reports-db" })
    workflow = published("Disk", steps: [ notice ])
    said = []
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_monitoring_notice).with { |**given| said << given[:notice] }
                    .returns({ channel_id: "C0MONITOR", message_id: "1.2" })

    run = start(workflow)

    assert_equal true, run.steps.find_by!(step_key: "raise").output["said"]
    raised = @workspace.investigation_notices.find_by!(topic: "Disk of reports-db")
    assert_nil raised.resource
    assert_equal "reports-db", raised.resource_words
    assert_equal [ raised ], said
    assert_includes Slack::Messages::MonitoringNotice.fields(raised), "*Resource:* reports-db"
    assert_equal "reports-db", InvestigationNoticeSerializer.one(raised)[:resourceName]
  end

  test "a workflow refuses runs past its runs per hour, and one live run per subject" do
    workflow = published("Busy", steps: [ step("pause", "delay", { "minutes" => 5 }) ],
                                 trigger: { "kind" => "manual", "inputs" => [ { "key" => "service", "question" => "Which service?" } ] })
    workflow.update!(subject_key: "{{inputs.service}}", runs_per_hour: 2)

    start(workflow, inputs: { "service" => "web" })
    assert_equal "Busy is already running for web, so this run did not start.", refusal(workflow, inputs: { "service" => "web" })

    start(workflow, inputs: { "service" => "api" })
    assert_match "already started 2 runs in the last hour", refusal(workflow, inputs: { "service" => "db" })
  end

  test "the limits are counted with the workflow, and for an event the workspace, locked until the run is made" do
    workflow = published("Busy", steps: [ step("pause", "delay", { "minutes" => 5 }) ])
    order = sequence("limits")
    Workflow.any_instance.expects(:lock!).in_sequence(order)
    Workspace.any_instance.expects(:lock!).in_sequence(order)
    Workflow.any_instance.expects(:rate_blocked_reason).in_sequence(order).returns(nil)
    Workflow::Run.expects(:open!).in_sequence(order).returns([ nil, true ])
    DefinedWorkflow.stubs(:launch!)

    WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: Workflow::Trigger::KIND_ALERT_RECEIVED)
  end

  test "publishing refuses a change with no undo or no check after it" do
    workflow = Workflow.create!(workspace: @workspace, name: "Restart", created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(steps: [ step("restart", "call_tool", { "tool" => "restart", "arguments" => { "resource" => "web" } }) ])

    problems = draft.reload.problems
    assert_includes problems, "restart changes something, so it needs its undo: how a person puts it back."
    assert_includes problems, "restart changes something, so a step that reads how it went needs to run after it."
  end

  test "a watch step starts the watch Halon keeps, as the workflow's identity, and takes the route it ended on" do
    spec = { "title" => "Deploy of web", "steps" => [ { "label" => "web", "capability" => "status", "resource" => "web", "done_when" => "running" } ] }
    Conversation::Watches.expects(:start).with do |host, given|
      Chat::Watch.create!(chat: host.chat, workspace: host.workspace, asker: host.asker, title: given["title"], expires_at: 1.hour.from_now,
                          limit_basis: Chat::Watch::BASIS_DEFAULT)
      host.conversation.personal? == false
    end.returns("Started")
    Workflow::Version.any_instance.stubs(:step_problems).returns([])
    watch = step("follow", "watch", spec)
    after = step("after", "delay", { "seconds" => 0 })
    workflow = published("Follow", steps: [ watch, after ], edges: [ edge("follow", "after", "succeeded") ])

    run = start(workflow)
    assert_equal Workflow::Run::STATUS_WAITING, run.status
    kept = Chat::Watch.sole
    assert_equal workflow.agent, kept.asker
    assert kept.workflow_step?

    perform_enqueued_jobs { Conversation::Watches.finish!(kept, Chat::Watch::STATUS_SUCCEEDED, "Done in 4 minutes.") }

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal({ "status" => "succeeded", "outcome" => "Done in 4 minutes." }, run.steps.find_by!(step_key: "follow").output)
    assert_equal "succeeded", run.steps.find_by!(step_key: "follow").route
  end

  test "a run that ends stops the watches its steps still keep" do
    workflow = published("Pause", steps: [ step("pause", "delay", { "minutes" => 5 }) ])
    run = start(workflow)
    record = run.steps.sole
    chat = Chat.open!(owner: record, workspace: @workspace, model_choice: FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace))
    kept = Chat::Watch.create!(chat: chat, workspace: @workspace, asker: workflow.agent, title: "Deploy", expires_at: 1.hour.from_now, limit_basis: Chat::Watch::BASIS_DEFAULT)

    perform_enqueued_jobs { SolidWorkflow::Workflow.find_by!(start_key: DefinedWorkflow.start_key_for(run)).cancel!(reason: "test", by: nil) }

    assert_equal Workflow::Run::STATUS_CANCELLED, run.reload.status
    assert_equal Chat::Watch::STATUS_STOPPED, kept.reload.status
  end

  test "a skill step follows the skill and reports what it found" do
    report = { "verdict" => "problem", "summary" => "Scanners walked /wp-admin on shop.", "severity" => "medium", "findings" => [ "203.0.113.4 asked for /wp-admin 400 times." ] }
    Workflow::HalonStep.any_instance.expects(:follow!).with(skill_name: "probing_scan", focus: "The last day.").returns(report)
    workflow = published("Probe", steps: [ step("scan", "run_skill", { "skill" => "probing_scan", "focus" => "The last day." }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal report.merge("problems" => []), run.steps.find_by!(step_key: "scan").output
  end

  test "a workflow cannot be published with a skill step whose skill the workspace switched off" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CUSTOM_SKILLS)
    skill = Chat::CustomSkill.create_with!(workspace: @workspace, name: "game_day", by: @alice,
                                           content: { "when" => "A drill", "tools" => [ "get_form" ], "steps" => "1. Read `get_form`." })
    skill.switch!(on: false)

    problems = DefinedWorkflow::Steps::RunSkill.problems(step("drill", "run_skill", { "skill" => "game_day" }), @workspace)

    assert_equal [ "drill follows game_day, which is switched off on the Skills page." ], problems
  end

  test "a halon step that cannot answer fails the step with why" do
    Workflow::HalonStep.any_instance.stubs(:follow!).returns({ "error" => "Halon is not set up for this workspace." })
    workflow = published("Probe", steps: [ step("scan", "run_skill", { "skill" => "probing_scan" }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_equal "scan failed. Halon is not set up for this workspace.", run.error
  end
end
