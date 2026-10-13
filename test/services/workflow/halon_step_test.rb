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
      tools.find { |tool| tool.name == Workflow::HalonStep::Report::NAME }.call(
        **{ "verdict" => "problem", "summary" => "Scanners walked shop.", "findings" => [],
          "problems" => [ { "topic" => "Probing of shop", "summary" => "203.0.113.4 asked for /wp-admin 400 times.", "severity" => "loud" }, { "topic" => "" } ] }
      )
      chat.owner == @record && skill_text.include?("probing")
    end

    report = Workflow::HalonStep.new(@run, @record).follow!(skill_name: "probing_scan", focus: "The last day.")

    problem = { "topic" => "Probing of shop", "summary" => "203.0.113.4 asked for /wp-admin 400 times.", "severity" => Investigation::Notice::SEVERITY_LOW }
    assert_equal({ "verdict" => "problem", "summary" => "Scanners walked shop.", "severity" => nil, "findings" => [], "problems" => [ problem ] }, report)
    assert_includes handed, Workflow::HalonStep::Report::NAME
    skill = Chat::Skill.find("probing_scan")
    assert (handed - [ Workflow::HalonStep::Report::NAME, Chat::Tools::ReadResult.tool_name ]).all? { |name| skill.tools.include?(name) }, handed.inspect
  end

  test "a problem keeps the day it becomes one only when it is a date, so a loose day never loses its notice" do
    problems = Workflow::HalonStep::Report.problems_of([
      { "topic" => "Certificate", "summary" => "It expires soon.", "due_on" => "2026-10-28" },
      { "topic" => "Disk", "summary" => "It fills up.", "due_on" => "next week" }
    ])

    assert_equal [ "2026-10-28", nil ], problems.map { |problem| problem["due_on"] }
    assert_equal %w[Certificate Disk], problems.map { |problem| problem["topic"] }
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

  test "a skill the workspace switched off is not followed, and the step says so" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CUSTOM_SKILLS)
    skill = Chat::CustomSkill.create_with!(workspace: @workspace, name: "game_day", by: @alice,
                                           content: { "when" => "A drill", "tools" => [ "get_form" ], "steps" => "1. Read `get_form`." })
    skill.switch!(on: false)
    FirefightAi::SkillFollower.any_instance.expects(:run).never

    assert_equal({ "error" => "game_day is switched off on the Skills page." }, Workflow::HalonStep.new(@run, @record).follow!(skill_name: "game_day", focus: nil))
  end
end
