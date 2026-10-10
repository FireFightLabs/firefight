require "application_system_test_case"

# A plan Halon keeps in a dashboard chat: a checklist that shows each step as it stands, why it stopped with done,
# failed and not started, Retry and Undo with Undo asking first, and Schedule on a plan waiting for its time, each
# confirmed with a toast.
class AgentPlanCardTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  STEPS = [
    { "kind" => "read", "description" => "Read the commit main is at", "place" => "GitHub" },
    { "kind" => "change", "description" => "Deploy region 1", "place" => "Northflank", "tool" => "northflank_deploy",
      "undo" => "Roll region 1 back to deploy d-41" },
    { "kind" => "change", "description" => "Deploy region 2", "place" => "Northflank", "tool" => "northflank_deploy",
      "undo" => "Roll region 2 back to deploy d-41" },
    { "kind" => "change", "description" => "Deploy region 3", "place" => "Northflank", "tool" => "northflank_deploy",
      "undo" => "Roll region 3 back to deploy d-41" },
    { "kind" => "check", "description" => "Check checkout's error rate and latency against normal", "place" => "checkout" }
  ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:unavailable_reason).returns(nil)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("Release main to production, one region at a time.")
    @conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT,
                                        content: "Region 1 is out. Region 2 failed: the provider said its quota is used up. Region 3 has not started.")
    @conversation.reply_delivered!
  end

  def make(**options)
    Chat::Plan.make!(chat: @conversation.chat, made_by: @alice, goal: "Release main to production, one region at a time", steps: STEPS.map(&:dup), **options)
  end

  test "a plan that half failed shows done, failed with why and not started, and Retry hands it back to Halon with a toast" do
    plan = make
    plan.move_step!(1, status: "done", note: "main is at 4f2a91c", links: [ "https://github.com/acme/shop/commit/4f2a91c" ])
    plan.move_step!(2, status: "done", note: "Deploy d-42 is live in region 1")
    plan.move_step!(3, status: "failed", note: "The provider said the region's build quota is used up")

    visit agent_chat_path(@conversation)

    assert_text "Plan stopped"
    assert_text "Release main to production, one region at a time"
    assert_text "Step 3 failed. The provider said the region's build quota is used up."
    assert_text "Undo: Roll region 1 back to deploy d-41"
    page.save_screenshot(Rails.root.join("tmp/screenshots/plan-card-stopped.png"))

    click_button "Retry"

    assert_text "Halon is trying the plan again."
    assert_text "Plan in progress"
    assert_no_button "Retry"
    assert plan.reload.active?
  end

  test "Undo asks first, then makes the undo from what each change was written with" do
    plan = make
    plan.move_step!(2, status: "done")
    plan.move_step!(3, status: "failed", note: "Quota used up")

    visit agent_chat_path(@conversation)
    click_button "Undo"
    assert_text "Undo this plan?"
    page.save_screenshot(Rails.root.join("tmp/screenshots/plan-card-undo-confirm.png"))
    click_button "Undo plan"

    assert_text "Halon is undoing the plan."
    assert_text "Undo in progress"
    assert_text "Put back step 2: Roll region 1 back to deploy d-41"
    assert_text "Plan cancelled"
    assert_no_button "Retry"
    page.save_screenshot(Rails.root.join("tmp/screenshots/plan-card-undo.png"))
  end

  test "a plan with a time waits for Schedule, which says when it runs" do
    make(run_at: 2.days.from_now.change(hour: 6), time_zone: "Europe/Berlin")

    visit agent_chat_path(@conversation)
    assert_text "Plan waiting for approval"
    page.save_screenshot(Rails.root.join("tmp/screenshots/plan-card-proposed.png"))
    click_button "Schedule"

    assert_text "Plan scheduled for"
    assert_text "Plan scheduled"
    assert_button "Cancel plan"
    assert_no_button "Schedule"
  end

  test "a finished plan ends with its outcome, its pages and the next step" do
    plan = make
    (1..4).each { |position| plan.move_step!(position, status: "done") }
    plan.move_step!(5, status: "done", verdict: "held", note: "Error rate 0.1%, normal 0.2%. p95 210 ms, normal 230 ms.")
    plan.finish!(outcome: "Main is live in all three regions and checkout is healthy.", next_step: "Shall I watch checkout's error rate for an hour?",
                 links: [ "https://app.northflank.com/s/acme/project/shop/services/checkout/deployments" ])

    visit agent_chat_path(@conversation)

    assert_text "Plan done"
    assert_text "Worked"
    assert_text "Next: Shall I watch checkout's error rate for an hour?"
    page.save_screenshot(Rails.root.join("tmp/screenshots/plan-card-done.png"))
  end
end
