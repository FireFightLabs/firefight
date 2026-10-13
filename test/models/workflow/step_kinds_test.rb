require "test_helper"

class Workflow::StepKindsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  def facts = Workflow::StepKinds::Facts.new(workspace: @workspace)

  def step(kind, config = {}) = { "kind" => kind, "config" => config }

  test "every kind the engine or the app runs is offered, and nothing else" do
    offered = Workflow::StepKinds.offered.map(&:key)

    assert_equal (DefinedWorkflow::STEP_KINDS + DefinedWorkflow.action_kinds).uniq.sort, offered.sort
    DefinedWorkflow::Steps.kinds.each { |klass| assert_includes offered, klass.kind }
  end

  test "a kind the app runs takes its name, group, outputs and what it changes from its own class" do
    post = Workflow::StepKinds.find(DefinedWorkflow::Steps::PostToChannel.kind)

    assert_equal [ "Post to channel", DefinedWorkflow::Steps::Base::GROUP_MESSAGES ], [ post.label, post.group ]
    assert_equal DefinedWorkflow::Steps::PostToChannel.output_fields({}), Workflow::StepKinds.outputs_of(step(post.key), facts)
    assert_equal Workflow::StepKinds::EFFECT_CHANGES, Workflow::StepKinds.effect_of(step(post.key), facts)
    assert_equal Workflow::StepKinds::EFFECT_READS, Workflow::StepKinds.effect_of(step(DefinedWorkflow::Steps::RunSkill.kind), facts)
    assert_equal [ Ability::Action::CHANNEL_POST ], Workflow::StepKinds.reach_of(step(post.key), facts).map(&:key)
  end

  test "a tool step reads or changes by what its tool does, never by what its author says" do
    DefinedWorkflow::Steps::CallTool.stubs(:changes?).with({ "tool" => "restart_service" }, @workspace).returns(true)
    DefinedWorkflow::Steps::CallTool.stubs(:changes?).with({ "tool" => "search_logs" }, @workspace).returns(false)

    assert_equal Workflow::StepKinds::EFFECT_CHANGES, Workflow::StepKinds.effect_of(step(Workflow::StepKinds::KIND_CALL_TOOL, "tool" => "restart_service"), facts)
    assert_equal Workflow::StepKinds::EFFECT_READS, Workflow::StepKinds.effect_of(step(Workflow::StepKinds::KIND_CALL_TOOL, "tool" => "search_logs"), facts)
  end

  test "a run skill step offers the workspace's own skills" do
    field = Workflow::StepKinds.find(DefinedWorkflow::Steps::RunSkill.kind).fields_for(facts).first

    assert_equal Chat::Skill.available_to(@workspace).map(&:name).sort, field.options
  end

  test "a branch's routes are its own and its otherwise, with the error route when it takes one on failure, and a watch's are how it ended" do
    branch = { "kind" => DefinedWorkflow::KIND_BRANCH, "config" => { "routes" => [ { "route" => "big" }, { "route" => "small" } ], "otherwise" => "none" } }

    assert_equal %w[big small none], Workflow::StepKinds.routes_of(branch)
    assert_equal %w[big small none error], Workflow::StepKinds.routes_of(branch.merge("on_failure" => DefinedWorkflow::ON_FAILURE_ERROR_ROUTE))
    assert_equal %w[received timed_out], Workflow::StepKinds.routes_of({ "kind" => DefinedWorkflow::KIND_WAIT_FOR_EVENT })
    assert_equal DefinedWorkflow::Steps::Watch::ROUTES, Workflow::StepKinds.routes_of(step(DefinedWorkflow::Steps::Watch.kind))
  end

  test "the engine's steps hand on the fields it gives them" do
    assert_equal %w[outcome event], Workflow::StepKinds.outputs_of({ "kind" => DefinedWorkflow::KIND_WAIT_FOR_EVENT }, facts)
  end

  test "a kind must name a group, an editor and an icon the canvas knows" do
    assert_raises(ArgumentError) do
      Workflow::StepKinds.register(Workflow::StepKinds::Kind.new(key: "x", group: "nowhere", label: "X", description: "X.",
                                                                 icon: Workflow::StepKinds::ICON_TOOL, editor: Workflow::StepKinds::EDITOR_FIELDS))
    end
  end

  test "schedule and once at are offered as triggers beside running by hand" do
    assert_equal [ Workflow::Trigger::KIND_MANUAL, Workflow::Trigger::KIND_SCHEDULE, Workflow::Trigger::KIND_ONCE_AT ], Workflow::TriggerKinds.all.map(&:key)
    assert_empty Workflow::Trigger.problems(Workflow::TriggerKinds.find(Workflow::Trigger::KIND_SCHEDULE).defaults
                                              .merge("kind" => Workflow::Trigger::KIND_SCHEDULE, "time_zone" => "Europe/Belgrade"))
  end
end
