require "test_helper"

class Workflow::HalonStepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    Investigation.stubs(:unavailable_reason).returns(nil)
    workflow = Workflow.create!(workspace: @workspace, name: "Probe", created_by: @alice)
    workflow.open_draft!(by: @alice).update!(steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "minutes" => 5 } } ])
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    perform_enqueued_jobs { @run = WorkflowRunService.new(workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }
    @record = @run.steps.sole
  end

  test "following a skill hands Halon only the skill's tools, reading as the workflow's identity, and keeps its report" do
    handed = nil
    FirefightAi::SkillFollower.any_instance.expects(:run).with do |chat:, tools:, skill_text:, **|
      handed = tools.map(&:name)
      tools.find { |tool| tool.name == Workflow::HalonStep::Report::NAME }.execute(verdict: "ok", summary: "Nothing probed shop.", findings: [])
      chat.owner == @record && skill_text.include?("probing")
    end

    report = Workflow::HalonStep.new(@run, @record).follow!(skill_name: "probing_scan", focus: "The last day.")

    assert_equal({ "verdict" => "ok", "summary" => "Nothing probed shop.", "severity" => nil, "findings" => [] }, report)
    assert_includes handed, Workflow::HalonStep::Report::NAME
    skill = Chat::Skill.find("probing_scan")
    assert (handed - [ Workflow::HalonStep::Report::NAME, Chat::Tools::ReadResult.tool_name ]).all? { |name| skill.tools.include?(name) }, handed.inspect
  end

  test "a skill this workspace does not have is refused in words" do
    assert_equal({ "error" => "There is no skill called nope for this workspace's connections." },
                 Workflow::HalonStep.new(@run, @record).follow!(skill_name: "nope", focus: nil))
  end

  test "nothing runs once the run's AI ceiling is spent" do
    @run.workflow.update!(cost_cap_cents: 10)
    Inference.create!(workspace: @workspace, inferable: @run, feature: FirefightAi::WorkflowAnswer::FEATURE, provider: "openai", model: "gpt", cost_micros: 100_000, status: "success")
    FirefightAi::WorkflowAnswer.any_instance.expects(:answer).never

    assert_equal({ "error" => Workflow::HalonStep::OUT_OF_ROOM }, Workflow::HalonStep.new(@run, @record).ask!(question: "Fine?", data: "x", fields: []))
    assert_equal 10, @run.ai_spent_cents
  end
end
