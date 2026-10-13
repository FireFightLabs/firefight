require "test_helper"

class Mcp::Tools::SkillsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::CUSTOM_SKILLS)
    @skill = Chat::CustomSkill.create_with!(workspace: @workspace, name: "game_day", by: @admin,
                                            content: { "when" => "Someone asks for a game day", "tools" => [ "declare_incident" ], "steps" => "1. Declare it." })
  end

  test "the workspace's skills are listed and one is read whole by its name or id" do
    listed = call(Mcp::Tools::ListSkills, @member).structured_content[:skills]
    assert_equal [ [ "game_day", true, 1 ] ], listed.map { |skill| skill.values_at(:name, :enabled, :version) }

    read = call(Mcp::Tools::GetSkill, @member, skill: "GAME_DAY").structured_content
    assert_equal [ "1. Declare it.", [ "declare_incident" ], @skill.live_version_id ], read.values_at(:steps, :tools, :version_id)
    assert call(Mcp::Tools::GetSkill, @member, skill: "nothing").error?
  end

  test "an admin adds a skill and changes one, each in the activity log, and a change over someone else's is refused" do
    added = call(Mcp::Tools::UpsertSkill, @admin, name: "rotate_keys", when: "Someone asks to rotate keys", tools: [ "declare_incident" ], steps: "1. Declare.")
    assert_equal "rotate_keys", added.structured_content[:name]
    assert_equal 1, Ability::Invocation.where(workspace: @workspace, action_key: "skills.create", source: AbilityGateway::SOURCE_MCP).count

    seen = @skill.live_version_id
    changed = call(Mcp::Tools::UpsertSkill, @admin, skill: "game_day", steps: "1. Page first.", version_id: seen, reason: "Page first.")
    assert_not changed.error?
    assert_equal [ "1. Page first.", "Someone asks for a game day", 2 ], @skill.reload.live_version.values_at(:steps, :used_when, :number)

    stale = call(Mcp::Tools::UpsertSkill, @admin, skill: "game_day", steps: "Over it", version_id: seen)
    assert_match "Someone changed this skill", stale.content.sole[:text]

    unknown = call(Mcp::Tools::UpsertSkill, @admin, name: "other", when: "x", tools: [ "launch_rockets" ], steps: "1.")
    assert_match "launch_rockets is not a tool Halon has in this workspace", unknown.content.sole[:text]
  end

  test "a skill is switched off and on through the same tool" do
    call(Mcp::Tools::UpsertSkill, @admin, skill: "game_day", enabled: false)
    assert_not @skill.reload.enabled?
    assert_equal 1, @skill.versions.count, "switching it changes no version"

    call(Mcp::Tools::UpsertSkill, @admin, skill: "game_day", enabled: true)
    assert @skill.reload.enabled?
  end

  test "deleting needs the permission and is refused while a workflow runs the skill" do
    assert call(Mcp::Tools::DeleteSkill, @member, skill: "game_day").error?

    Workflow.create!(workspace: @workspace, name: "Drill").open_draft!(by: @admin)
            .update_columns(steps: [ { "id" => "step_1", "name" => "drill", "kind" => "run_skill", "config" => { "skill" => "game_day" } } ])
    refused = call(Mcp::Tools::DeleteSkill, @admin, skill: "game_day")
    assert_match "take it out of that workflow", refused.content.sole[:text]

    Workflow.where(workspace: @workspace).destroy_all
    assert_not call(Mcp::Tools::DeleteSkill, @admin, skill: "game_day").error?
    assert_not Chat::CustomSkill.exists?(@skill.id)
  end

  test "the tools exist only with the custom skills flag and are not offered to Halon" do
    names = [ Mcp::Tools::LIST_SKILLS, Mcp::Tools::GET_SKILL, Mcp::Tools::UPSERT_SKILL, Mcp::Tools::DELETE_SKILL ]
    assert_empty names - Mcp::Tools.available_in(@workspace).map { |tool| tool.name_value.to_s }
    assert_empty names - Chat::Tools::Groups::NOT_FOR_HALON

    FeatureFlags.disable!(@workspace, FeatureFlags::CUSTOM_SKILLS)
    assert_empty names & Mcp::Tools.available_in(@workspace).map { |tool| tool.name_value.to_s }
  end

  private

  def call(tool, principal, **args)
    Mcp::ToolDispatcher.call(tool: tool, server_context: { workspace: @workspace, principal: principal }, args: args)
  end
end
