require "test_helper"

# Plans Halon keeps in a chat, through the tools it calls and what happens around them: the checklist it reads every
# turn, the message in Slack, and a scheduled plan that runs at its time only after a fresh reading and outside a freeze.
class Conversation::PlansTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  STEPS = [
    { "kind" => "read", "description" => "Read the latest commit on main", "place" => "GitHub" },
    { "kind" => "change", "description" => "Start the release workflow", "place" => "GitHub", "tool" => "github_run_workflow",
      "undo" => "Roll checkout back to the deploy before" },
    { "kind" => "check", "description" => "Check checkout against normal", "place" => "checkout" }
  ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @chat = @conversation.chat_record
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @adapter = stub(post_chat_plan: { channel_id: "C1", message_id: "1.1" }, post_chat_plan_to_user: { channel_id: "D1", message_id: "2.2" },
                    update_chat_plan: { success: true }, get_user_info: { timezone: "Europe/Berlin" })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
    Investigation.stubs(:unavailable_reason).returns(nil)
    Chat::Tools.stubs(:catalog).returns([
      Chat::Tools::Entry.new(name: "github_run_workflow", description: "Run a workflow", state: Chat::Tools::STATE_READY, tool: nil,
                             group: nil, source: "github", handle: "run_workflow")
    ])
  end

  def call(tool_class, **arguments)
    tool_class.new(@turn).call(tool_call: nil, **arguments)
  end

  def make(**options)
    Chat::Plan.make!(chat: @chat, made_by: @alice, goal: "Release main to production", steps: STEPS.map(&:dup), **options)
  end

  test "make_plan keeps the plan, tells the page, and hands Halon the checklist to say back" do
    ConversationChannel.expects(:broadcast_to).with(@conversation, type: Conversation::LiveDelivery::EVENT_PLAN)

    said = call(Conversation::Tools::MakePlan, goal: "Release main to production", steps: STEPS)

    plan = @chat.plans.sole
    assert plan.active?
    assert_match "Say it to the person in two short lines", said
    assert_match "2. [not started] change in GitHub: Start the release workflow Tool: github_run_workflow. Undo: Roll checkout back", said
  end

  test "a refused plan says why and marks the call failed" do
    Chat::Tools.expects(:mark_failed).with(@turn, nil)

    said = call(Conversation::Tools::MakePlan, goal: "Release", steps: STEPS.first(2))

    assert_match "Not made. A plan that changes something ends with a check step", said
    assert_empty @chat.plans
  end

  test "a time with no zone is read in the person's own, and a time in a dashboard chat goes to their direct messages once approved" do
    travel_to Time.zone.parse("2026-10-10 12:00 UTC")
    said = call(Conversation::Tools::MakePlan, goal: "Release main", steps: STEPS, run_at: "2026-10-17T06:00")

    plan = @chat.plans.sole
    assert_equal [ Chat::Plan::STATUS_PROPOSED, Time.zone.parse("2026-10-17 04:00 UTC"), "Europe/Berlin" ], [ plan.status, plan.run_at, plan.time_zone ]
    assert_match "Proposed for Saturday 17 October at 06:00 CEST", said
    assert_not Conversation::Plans.posted?(plan)

    assert_nil Conversation::Plans.approve!(plan, by: @alice)
    assert Conversation::Plans.posted?(plan.reload)
    @adapter.expects(:post_chat_plan_to_user).with(user_id: @alice.platform_user_id, plan: plan, conversation_id: @conversation.id).returns(channel_id: "D1", message_id: "2.2")
    Conversation::Plans.tell!(plan)
    assert_equal [ "D1", "2.2" ], [ plan.reload.message_channel_id, plan.message_id ]

    @adapter.expects(:update_chat_plan).with(channel_id: "D1", message_id: "2.2", plan: plan, direct: true, conversation_id: @conversation.id)
    Conversation::Plans.tell!(plan)
  end

  test "a scheduled change names a tool the person may call that changes something, since that is what they approve" do
    steps = [ STEPS[0], STEPS[1].merge("tool" => "aws_delete_stack"), STEPS[2] ]

    said = call(Conversation::Tools::MakePlan, goal: "Release main", steps: steps, run_at: 2.days.from_now.strftime("%Y-%m-%dT06:00"))

    assert_match "aws_delete_stack is not a tool Alice Smith may call that changes something", said
    assert_empty @chat.plans
  end

  test "without a known time zone Halon is told to ask" do
    @adapter.stubs(:get_user_info).returns(timezone: nil)

    said = call(Conversation::Tools::MakePlan, goal: "Release main", steps: STEPS, run_at: "2026-10-17T06:00")

    assert_match "Ask the person which time zone they mean", said
  end

  test "an outside agent's chat cannot schedule, since nobody there can approve it" do
    mcp = Conversation.for_mcp!(workspace: @workspace, principal: @alice)
    mcp.chat_record
    @turn = Conversation::Turn.new(mcp, asker: @alice)

    said = call(Conversation::Tools::MakePlan, goal: "Release main", steps: STEPS, run_at: 2.days.from_now.iso8601)

    assert_match "nobody in this chat can", said
  end

  test "a chat in a thread shows its plan there from the start" do
    @conversation.update!(kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "111.1")
    plan = make

    assert_enqueued_with(job: ChatPlanMessageJob, args: [ plan.id ]) { Conversation::Plans.moved!(plan) }
    @adapter.expects(:post_chat_plan).with(channel_id: "C1", thread_id: "111.1", plan: plan).returns(channel_id: "C1", message_id: "1.1")
    perform_enqueued_jobs(only: ChatPlanMessageJob)
  end

  test "update_plan moves a step, and a failed change stops the plan and says done, failed and not started" do
    plan = make
    call(Conversation::Tools::UpdatePlan, step: 1, status: "done", note: "main is at abc123")

    said = call(Conversation::Tools::UpdatePlan, step: 2, status: "failed", note: "The provider said the workflow file is missing")

    assert plan.reload.stopped?
    assert_match "The plan stopped. Step 2 failed. The provider said the workflow file is missing.", said
    assert_match "Done: step 1. Failed: step 2.", said
    assert_match "Not started: step 3. The plan card offers Retry.", said
  end

  test "a check after a change is marked done only after a reading through a connection since the change ended" do
    plan = make
    call(Conversation::Tools::UpdatePlan, step: 1, status: "done")
    call(Conversation::Tools::UpdatePlan, step: 2, status: "done")

    said = call(Conversation::Tools::UpdatePlan, step: 3, status: "done", verdict: "held", note: "Error rate 0.1%, normal 0.2%")
    assert_match "Not updated. Read how it stands since the last change ended", said

    message = @chat.add_message(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: ResourceMap::KeyQueries::TOOL_NAME, arguments: {})
    said = call(Conversation::Tools::UpdatePlan, step: 3, status: "done", verdict: "held", note: "Error rate 0.1%, normal 0.2%")

    assert_match "Every step has ended, so finish it with finish_plan", said
    assert_equal "held", plan.steps.reload.last.verdict
  end

  test "finish_plan ends it with the outcome, the links and the next step" do
    plan = make
    plan.move_step!(1, status: "done")
    plan.move_step!(2, status: "done")
    plan.move_step!(3, status: "done", verdict: "held")

    said = call(Conversation::Tools::FinishPlan, outcome: "Release 1.4 is live and healthy.", next_step: "Shall I watch it for an hour?",
                                                 links: [ "https://github.com/acme/shop/actions/runs/46" ])

    assert_match "Finished. Now report it to the person", said
    assert_equal [ Chat::Plan::STATUS_COMPLETED, [ "https://github.com/acme/shop/actions/runs/46" ] ], [ plan.reload.status, plan.links ]
  end

  test "with two plans going Halon is asked which it means" do
    first = make
    second = make

    said = call(Conversation::Tools::UpdatePlan, step: 1, status: "running")
    assert_match "This chat has 2 plans going", said

    call(Conversation::Tools::UpdatePlan, plan: second.id, step: 1, status: "running")
    assert [ first.steps.first.reload.not_started?, second.steps.first.reload.running? ].all?
  end

  test "cancel_plan ends a scheduled plan so it never runs" do
    plan = make(run_at: 2.days.from_now, time_zone: "UTC")

    said = call(Conversation::Tools::CancelPlan, reason: "The person wants Monday instead")

    assert_match "Cancelled", said
    assert_equal [ Chat::Plan::STATUS_CANCELLED, "The person wants Monday instead." ], [ plan.reload.status, plan.stop_reason ]
  end

  test "every turn Halon reads the plans in play, with each step, its undo and what it said" do
    plan = make
    plan.move_step!(1, status: "done", note: "main is at abc123")
    make.cancel!

    said = Conversation::Plans.for_halon(@chat)

    assert_match "Plan #{plan.id} (active): Release main to production", said
    assert_match "1. [done] read in GitHub: Read the latest commit on main Said: main is at abc123", said
    assert_equal 1, said.scan("Plan ").size
  end

  test "at its time a scheduled plan reads how things stand and hands the plan to Halon as whoever approved it" do
    plan = make(run_at: 1.hour.from_now, time_zone: "UTC")
    plan.approve!(by: @bob)
    Chat::StateCheck.expects(:run).with do |owner:, principal:, call:, **|
      owner == plan && principal == @bob && call.named == "the plan to Release main to production"
    end.returns(Chat::CurrentState::Report.new(state: "checkout runs deploy d-41, healthy.", change: Chat::CurrentState::UNCHANGED))

    travel 2.hours do
      perform_enqueued_jobs(only: ChatPlanRunJob) { ChatPlanSweepJob.perform_now }
    end

    assert_equal [ Chat::Plan::STATUS_ACTIVE, "checkout runs deploy d-41, healthy." ], [ plan.reload.status, plan.state_now ]
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @bob.id, nil, nil, nil, nil, plan.id, Conversation::Plans::MOVE_RUN ])
    note = Conversation::Plans.note(plan, Conversation::Plans::MOVE_RUN, @bob)
    assert_match "github_run_workflow run without asking again. Approval rules still apply.", note
  end

  test "a reading that says things moved stops a scheduled plan before anything runs" do
    plan = make(run_at: 1.hour.from_now, time_zone: "UTC")
    plan.approve!(by: @alice)
    Chat::StateCheck.stubs(:run).returns(Chat::CurrentState::Report.new(state: "checkout already runs 1.4.", change: Chat::CurrentState::DONE_ALREADY))

    travel(2.hours) { Conversation::Plans.run_scheduled!(plan) }

    assert plan.reload.stopped?
    assert_equal "This looks done already. checkout already runs 1.4. Nothing ran.", plan.stop_reason
    assert_no_enqueued_jobs(only: ConversationReplyJob)
  end

  test "a freeze at its time stops a scheduled plan without reading anything" do
    plan = make(run_at: 1.hour.from_now, time_zone: "UTC")
    plan.approve!(by: @alice)
    window = Workspace::FreezeWindows::Window.new(name: "the launch", starts_at: 90.minutes.from_now, ends_at: 1.day.from_now)
    Workspace::FreezeWindows.stubs(:all).returns([ window ])
    Chat::StateCheck.expects(:run).never

    travel(2.hours) { Conversation::Plans.run_scheduled!(plan) }

    assert_match "Changes are frozen for the launch until", plan.reload.stop_reason
    assert_match "Nothing ran.", plan.stop_reason
  end

  test "a plan is started once however many sweeps reach it" do
    plan = make(run_at: 1.hour.from_now, time_zone: "UTC")
    plan.approve!(by: @alice)
    Chat::StateCheck.expects(:run).once.returns(Chat::CurrentState::Report.new(state: "fine", change: Chat::CurrentState::UNCHANGED))

    travel 2.hours do
      Conversation::Plans.run_scheduled!(plan)
      Conversation::Plans.run_scheduled!(Chat::Plan.find(plan.id))
    end
  end

  test "Slack's buttons do what the dashboard's do, and a press someone may not make is answered privately" do
    plan = make(run_at: 2.days.from_now, time_zone: "UTC")
    interaction = Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, workspace: @workspace, user_id: @bob.platform_user_id,
                                  action_id: Identifiers::CHAT_PLAN_SCHEDULE, action_value: plan.id, channel_id: "D9")
    @adapter.expects(:post_ephemeral).with(channel_id: "D9", user_id: @bob.platform_user_id, text: "Only Alice Smith can do that.")
    @workspace.stubs(:adapter).returns(@adapter)

    Interactions::ChatPlanHandler.execute(interaction)
    assert plan.reload.proposed?

    @conversation.update!(kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "111.1")
    Interactions::ChatPlanHandler.execute(interaction)
    assert_equal [ Chat::Plan::STATUS_SCHEDULED, @bob ], [ plan.reload.status, plan.approved_by ]
  end
end
