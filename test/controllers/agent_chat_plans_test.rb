require "test_helper"

# A plan in a dashboard chat: its checklist on the page, and Schedule, Cancel, Retry and Undo, each saying it happened.
class AgentChatPlansTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  STEPS = [
    { "kind" => "read", "description" => "Read the latest commit on main", "place" => "GitHub" },
    { "kind" => "change", "description" => "Start the release workflow", "place" => "GitHub", "tool" => "github_run_workflow",
      "undo" => "Roll checkout back to the deploy before" },
    { "kind" => "check", "description" => "Check checkout against normal", "place" => "checkout" }
  ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:unavailable_reason).returns(nil)
    ConversationChannel.stubs(:broadcast_to)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @chat = @conversation.chat_record
  end

  def make(**options)
    Chat::Plan.make!(chat: @chat, made_by: @member, goal: "Release main to production", steps: STEPS.map(&:dup), **options)
  end

  test "the chat shows the plan as a checklist with what the viewer may press" do
    travel_to Time.zone.parse("2026-10-10 12:00 UTC")
    plan = make(run_at: Time.zone.parse("2026-10-17 06:00 +02:00"), time_zone: "Europe/Berlin")

    get agent_chat_url(@conversation), headers: inertia_headers

    shown = inertia_props[AgentChatsController::PROP_PLANS].sole
    assert_equal [ plan.id, "Plan waiting for approval", "Release main to production" ], shown.values_at("id", "heading", "goal")
    assert_equal "Runs Saturday 17 October at 06:00 CEST.", shown["progress"]
    assert_equal [ [ 1, "read", "not_started" ], [ 2, "change", "not_started" ], [ 3, "check", "not_started" ] ],
                 shown["steps"].map { |step| step.values_at("position", "kind", "status") }
    assert_equal "Roll checkout back to the deploy before", shown["steps"][1]["undo"]
    assert_equal [ { "action" => "schedule", "blockedReason" => nil }, { "action" => "cancel", "blockedReason" => nil } ], shown["offers"]
  end

  test "Schedule approves it for its time with a toast, and it runs then as whoever approved it" do
    plan = make(run_at: 2.days.from_now.change(hour: 6), time_zone: "UTC")

    post agent_chat_plan_schedule_url(@conversation, plan)

    assert_redirected_to agent_chat_url(@conversation)
    assert_equal "Plan scheduled for #{plan.reload.run_at_words}.", flash[:notice]
    assert_equal [ Chat::Plan::STATUS_SCHEDULED, @member ], [ plan.status, plan.approved_by ]
    assert_enqueued_with(job: ChatPlanMessageJob, args: [ plan.id ])
  end

  test "Cancel ends a plan waiting for its time with a toast, and nothing in it runs" do
    plan = make(run_at: 2.days.from_now, time_zone: "UTC")

    post agent_chat_plan_cancel_url(@conversation, plan)

    assert_equal "Plan cancelled. Nothing in it will run.", flash[:notice]
    assert_equal [ Chat::Plan::STATUS_CANCELLED, "#{@member.display_name} cancelled it." ], [ plan.reload.status, plan.stop_reason ]
  end

  test "Retry takes up a stopped plan with a toast and hands it to Halon as whoever pressed it" do
    plan = make
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_FAILED, note: "Quota exceeded")

    post agent_chat_plan_retry_url(@conversation, plan)

    assert_equal "Halon is trying the plan again.", flash[:notice]
    assert plan.reload.active?
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @member.id, nil, nil, nil, nil, plan.id, Conversation::Plans::MOVE_RETRY ])
  end

  test "Undo makes the undo from what each change was written with, with a toast, and hands it to Halon" do
    plan = make
    plan.move_step!(2, status: Chat::Plan::Step::STATUS_DONE)
    plan.move_step!(3, status: Chat::Plan::Step::STATUS_DONE, verdict: Chat::Plan::Step::VERDICT_NOT_HELD)

    post agent_chat_plan_undo_url(@conversation, plan)

    assert_equal "Halon is undoing the plan.", flash[:notice]
    undo = plan.reload.undo_plan
    assert_equal [ Chat::Plan::STATUS_CANCELLED, "#{@member.display_name} pressed Undo." ], [ plan.status, plan.stop_reason ]
    assert_equal [ "Undo: Release main to production", Chat::Plan::STATUS_ACTIVE ], [ undo.goal, undo.status ]
    assert_equal [ "Put back step 2: Roll checkout back to the deploy before", "Check it is back to how it was before: health, error rate and latency against normal" ],
                 undo.steps.map(&:description)
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @member.id, nil, nil, nil, nil, undo.id, Conversation::Plans::MOVE_UNDO ])
  end

  test "a press the plan does not take says why" do
    plan = make

    post agent_chat_plan_undo_url(@conversation, plan)
    assert_equal "Undo is offered once the plan has stopped or finished.", flash[:alert]

    post agent_chat_plan_schedule_url(@conversation, plan)
    assert_equal "This plan is not waiting to be scheduled.", flash[:alert]
  end

  test "a time inside a freeze is not approved" do
    plan = make(run_at: 2.days.from_now, time_zone: "UTC")
    Workspace::FreezeWindows.stubs(:all).returns([ Workspace::FreezeWindows::Window.new(name: "the launch", starts_at: 1.day.from_now, ends_at: 3.days.from_now) ])

    post agent_chat_plan_schedule_url(@conversation, plan)

    assert_match "Changes are frozen for the launch until", flash[:alert]
    assert plan.reload.proposed?
  end
end
