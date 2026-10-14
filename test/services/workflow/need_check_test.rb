require "test_helper"

# Before a change a run nobody pressed makes, Halon reads whether the problem it answers is still there.
class Workflow::NeedCheckTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    Investigation.stubs(:unavailable_reason).returns(nil)
    @workflow = Workflow.create!(workspace: @workspace, name: "Restart web", created_by: @alice)
    @workflow.open_draft!(by: @alice).update!(steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "minutes" => 5 } } ])
    WorkflowPublishService.new(@workflow).publish!(@workflow.draft, by: @alice)
    perform_enqueued_jobs do
      @run = WorkflowRunService.new(@workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: Workflow::Trigger::KIND_ALERT_RECEIVED,
                                                             trigger_payload: { "alert" => { "title" => "web answers 503" } })
    end
    @record = @run.steps.sole
    @call = Workflow::NeedCheck::Call.new(named: "Restart web on Faylee", asked: [ [ "resource", "web" ] ])
  end

  def check = Workflow::NeedCheck.run(run: @run, owner: @record, call: @call)

  test "Halon reads as the workflow's own identity on the step's chat, told what started the run, and says whether it is still needed" do
    FirefightAi::NeedChecker.any_instance.expects(:run).with do |chat:, tools:, max_spend_cents:, **|
      assert_equal @record, chat.owner
      asked = chat.messages.last.content
      assert_match "Restart web, a workflow, is about to make this change", asked
      assert_match "web answers 503", asked
      assert_match "Restart web on Faylee", asked
      assert_equal @workspace.conversation_limits.max_spend_cents, max_spend_cents
      tools.find { |tool| tool.name == Workflow::NeedCheck::Report::NAME }.execute(now: "web answers 200 again.", verdict: "cleared")
    end

    found = check

    assert_equal [ Workflow::NeedCheck::CLEARED, "web answers 200 again." ], [ found.verdict, found.state ]
  end

  test "it spends only what is left of the run's spending ceiling, and nothing once that is spent" do
    @workflow.update!(cost_cap_cents: 50)
    Workflow::Run.any_instance.stubs(:spent_cents).returns(20)
    FirefightAi::NeedChecker.any_instance.expects(:run).with { |max_spend_cents:, **| max_spend_cents == 30 }

    assert_equal Workflow::NeedCheck::UNKNOWN, check.verdict

    Workflow::Run.any_instance.stubs(:spent_cents).returns(50)
    FirefightAi::NeedChecker.any_instance.expects(:run).never
    spent = check

    assert_equal [ Workflow::NeedCheck::UNKNOWN, "This run reached its spending ceiling, so Halon did not check." ], [ spent.verdict, spent.state ]
  end

  test "a verdict that is none of the three reads as unknown, and so does Halon being off" do
    assert_equal Workflow::NeedCheck::UNKNOWN, Workflow::NeedCheck::Verdict.new(state: "x", verdict: "maybe").verdict

    Investigation.stubs(:unavailable_reason).returns("Investigations are not turned on for this workspace.")
    off = check
    assert_equal [ Workflow::NeedCheck::UNKNOWN, "Investigations are not turned on for this workspace." ], [ off.verdict, off.state ]
  end
end
