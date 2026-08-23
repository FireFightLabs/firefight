require "test_helper"

class AgentTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @agent = Agent.create!(workspace: @workspace, name: "Firefight Investigator", slug: "investigator")
  end

  test "slug is unique per workspace and machine-friendly" do
    duplicate = Agent.new(workspace: @workspace, name: "Other", slug: "investigator")
    assert_not duplicate.valid?

    assert_not Agent.new(workspace: @workspace, name: "Bad", slug: "Not A Slug").valid?
  end

  test "implements the principal contract" do
    assert_equal "agent:Firefight Investigator", @agent.principal_label
    assert_equal "agent", @agent.actor_kind
    assert_nil @agent.platform_user_id
  end

  test "reads nothing without grants, unlike human principals" do
    assert_not @agent.mcp_readable?(ApiKey::RESOURCE_INCIDENTS)

    Ability::Grant.create!(workspace: @workspace, principal: @agent, action: ability_actions(:incidents_read))
    assert @agent.mcp_readable?(ApiKey::RESOURCE_INCIDENTS)
    assert_not @agent.mcp_readable?(ApiKey::RESOURCE_ALERTS)
  end

  test "active scope excludes disabled and deleted agents" do
    @agent.update!(enabled: false)
    assert_not_includes Agent.active, @agent

    @agent.update!(enabled: true, deleted_at: Time.current)
    assert_not_includes Agent.active, @agent
  end
end
