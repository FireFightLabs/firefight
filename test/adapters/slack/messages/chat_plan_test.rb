require "test_helper"

# A plan Halon keeps for a chat, as Slack shows it: a checklist redrawn in place, what stopped it, how it ended, and the
# buttons its state offers.
class Slack::Messages::ChatPlanTest < ActiveSupport::TestCase
  STEPS = [
    { "kind" => "read", "description" => "Read the latest commit on main", "place" => "GitHub" },
    { "kind" => "change", "description" => "Start the release workflow", "place" => "GitHub", "tool" => "github_run_workflow",
      "undo" => "Roll checkout back to the deploy before" },
    { "kind" => "check", "description" => "Check checkout against normal", "place" => "checkout" }
  ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
  end

  def make(**options)
    Chat::Plan.make!(chat: @conversation.chat_record, made_by: @alice, goal: "Release main <to> production", steps: STEPS.map(&:dup), **options)
  end

  def texts(blocks) = blocks.filter_map { |block| block.dig(:text, :text) }

  def actions(blocks) = blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }

  test "a plan in progress is a titled checklist with a divider, its goal quoted and escaped, and each step marked" do
    plan = make
    plan.move_step!(1, status: "done", note: "main is at abc123")
    plan.move_step!(2, status: "running")

    blocks = Slack::Messages::ChatPlan.build(plan)

    assert_equal ":clipboard:  *Plan in progress*", texts(blocks).first
    assert_equal "divider", blocks[1][:type]
    assert_equal "> Release main &lt;to&gt; production\n1 of 3 steps done.", texts(blocks)[1]
    assert_equal ":white_check_mark: 1. Read the latest commit on main · GitHub\n      main is at abc123\n" \
                 ":hourglass_flowing_sand: 2. Start the release workflow · GitHub · runs Github run workflow\n:white_circle: 3. Check checkout against normal · checkout", texts(blocks)[2]
    assert_empty actions(blocks)
  end

  test "a stopped plan says why, what is done, failed and not started, and offers Retry and Undo, Undo asking first" do
    plan = make
    plan.move_step!(2, status: "done")
    plan.move_step!(3, status: "done", verdict: "not_held", note: "Errors at 4%, normal 0.2%")

    blocks = Slack::Messages::ChatPlan.build(plan.reload)

    assert_equal ":octagonal_sign:  *Plan stopped*", texts(blocks).first
    assert_match "The check found the changes did not work. Errors at 4%, normal 0.2%.", texts(blocks).last
    assert_match ":white_circle: 1. Read the latest commit on main", texts(blocks)[2]
    assert_equal [ Identifiers::CHAT_PLAN_RETRY, Identifiers::CHAT_PLAN_UNDO ], actions(blocks).pluck(:action_id)
    assert_equal "Undo this plan?", actions(blocks).last.dig(:confirm, :title, :text)
  end

  test "a plan waiting for approval says when it runs and offers Schedule and Cancel, and in direct messages Open the chat" do
    with_app_host do
      plan = make(run_at: 2.days.from_now.change(hour: 6), time_zone: "UTC")

      blocks = Slack::Messages::ChatPlan.build(plan, direct: true, conversation_id: @conversation.id)

      assert_equal ":calendar:  *Plan waiting for approval*", texts(blocks).first
      assert_match "Runs #{plan.run_at_words}.", texts(blocks)[1]
      assert_equal [ "Schedule", "Cancel plan", "Open the chat" ], actions(blocks).map { |element| element.dig(:text, :text) }
    end
  end

  test "a finished plan ends with its outcome, its pages as links and the next step" do
    plan = make
    plan.move_step!(1, status: "done")
    plan.move_step!(2, status: "done")
    plan.move_step!(3, status: "done", verdict: "held")
    plan.finish!(outcome: "Release 1.4 is live.", next_step: "Shall I watch it for an hour?", links: [ "https://github.com/acme/shop/actions/runs/46" ])

    said = texts(Slack::Messages::ChatPlan.build(plan)).last

    assert_equal "Release 1.4 is live.\n<https://github.com/acme/shop/actions/runs/46|github.com/acme/shop/actions/runs/46>\n*Next:* Shall I watch it for an hour?", said
    assert_equal "Plan done: Release main <to> production. 3 of 3 steps done.", Slack::Messages::ChatPlan.fallback(plan)
  end

  private

  def with_app_host
    previous = ENV["APP_HOST"]
    ENV["APP_HOST"] = "app.example.com"
    yield
  ensure
    ENV["APP_HOST"] = previous
  end
end
