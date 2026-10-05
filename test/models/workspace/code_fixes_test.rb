require "test_helper"

class Workspace::CodeFixesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @devin = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "devin", name: "Devin for web", slug: "devin_web")
    @devin.integration_environments.create!
  end

  test "Firefight's own agent writes code fixes until an admin chooses a connected coding agent" do
    assert_nil @workspace.code_fix_agent
    assert_nil @workspace.code_fix_agent_blocked_reason
    assert_equal [ [ nil, "Firefight's own agent" ], [ "devin_web", "Devin for web (Devin)" ] ], @workspace.code_fix_agent_choices.map { |choice| [ choice.value, choice.label ] }

    @workspace.update!(code_fix_agent: " devin_web ")

    assert_equal "devin_web", @workspace.reload.code_fix_agent
  end

  test "a connection that is not a coding agent, or belongs to another workspace, cannot be chosen" do
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    workspaces(:slack_workspace_two).integrations.create!(kind: Integration::KIND_NATIVE, provider: "cursor", name: "Cursor", slug: "cursor")

    assert_not @workspace.update(code_fix_agent: "github")
    assert_not @workspace.update(code_fix_agent: "cursor")
    assert_equal [ "is not a coding agent connected to this workspace" ], @workspace.errors[:code_fix_agent]
  end

  test "the chosen agent runs only while its tool is on, and the screen says why not otherwise" do
    @workspace.update!(code_fix_agent: "devin_web")
    assert_nil @workspace.code_fix_agent_tool
    assert_equal "Devin for web's fix_code tool is switched off, so code steps wait for a person. Switch it on under Integrations.", @workspace.code_fix_agent_blocked_reason

    tool = @devin.tools.create!(name: "fix_code", description: "Hands a change to Devin", params_schema: {}, enabled: true, read_only: false)
    assert_equal tool, @workspace.code_fix_agent_tool
    assert_nil @workspace.code_fix_agent_blocked_reason

    @devin.update!(disabled_at: Time.current)
    assert_nil @workspace.code_fix_agent_tool
    assert_equal "Devin for web is switched off, so code steps wait for a person until it is switched on again.", @workspace.code_fix_agent_blocked_reason

    @devin.update!(deleted_at: Time.current)
    assert_equal "The coding agent chosen to write code fixes was removed, so code steps wait for a person. Choose another one.", @workspace.code_fix_agent_blocked_reason
    assert_equal [ nil ], @workspace.code_fix_agent_choices.map(&:value), "a removed connection is no longer offered"
  end
end
