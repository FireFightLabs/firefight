require "test_helper"

class Mcp::Tools::UpdateProtectedPathsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
  end

  test "an admin adds and removes paths, the call is in the activity log, and the answer is the whole list" do
    added = call(@admin, connection: "github", add: [ ".github/workflows/", "infra/prod/**" ])

    assert_equal [ ".github/workflows/", "infra/prod/**" ], @github.reload.protected_paths
    assert_equal [ ".github/workflows/", "infra/prod/**" ], added.structured_content[:protected_paths]
    assert_equal "Halon may not change .github/workflows/ and infra/prod/** in GitHub's repositories.", added.structured_content[:said]
    assert_equal "Integrations, GitHub, Code changes", added.structured_content[:changed_on]
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: "integrations.update", principal: @admin)
    assert_equal AbilityGateway::SOURCE_MCP, invocation.source

    call(@admin, connection: "github", remove: [ ".github/workflows/" ], add: [ "*.lock" ])

    assert_equal [ "infra/prod/**", "*.lock" ], @github.reload.protected_paths
  end

  test "a path that is not on the list, or cannot be read, is refused with why and nothing changes" do
    @github.protect_paths!([ ".github/" ])

    missing = call(@admin, connection: "github", remove: [ "docs/" ])
    assert missing.error?
    assert_equal "docs/ is not on GitHub's list, which holds .github/.", missing.content.sole[:text]

    unread = call(@admin, connection: "github", add: [ "*.{lock,sum}" ])
    assert unread.error?
    assert_match "uses [ ], { } or \\", unread.content.sole[:text]

    assert call(@admin, connection: "github").error?
    assert call(@admin, connection: "nothing", add: [ "x/" ]).error?
    assert_equal [ ".github/" ], @github.reload.protected_paths
  end

  test "a member is refused, since the list decides what Halon may change" do
    refused = call(workspace_memberships(:bob_workspace_one), connection: "github", add: [ ".github/" ])

    assert refused.error?
    assert_equal [], @github.reload.protected_paths
  end

  test "the schema offers only code host connections, and a chat asks before it applies" do
    @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.example/mcp" })

    described = Mcp::Tools::UpdateProtectedPaths.schema_for(@workspace).dig(:properties, :connection, :description)

    assert_includes described, "The only one is github (GitHub)"
    assert Mcp::Tools::UpdateProtectedPaths.annotations_value.destructive_hint
    action = Ability::Action.find_by!(key: "integrations.update")
    conversation = @workspace.conversations.create!(kind: Conversation::KIND_PERSONAL, started_by: @admin, max_turns: 10, max_spend_cents: 40)
    assert Conversation::Turn.new(conversation, asker: @admin).confirms?(action, tool_name: Mcp::Tools::UPDATE_PROTECTED_PATHS, declared_destructive: true)
  end

  test "list_integrations shows each code host connection's paths" do
    @github.protect_paths!([ "*.lock" ])

    code = Mcp::Tools::ListIntegrations.perform(workspace: @workspace, args: { category: "code" }).structured_content
    github = code[:providers].find { |row| row[:key] == "github" }
    sentry = Mcp::Tools::ListIntegrations.perform(workspace: @workspace, args: { category: "observability" }).structured_content[:providers].first

    assert_equal({ "github" => [ "*.lock" ] }, github[:protected_paths])
    assert_not sentry.key?(:protected_paths)
  end

  private

  def call(principal, **args)
    Mcp::ToolDispatcher.call(tool: Mcp::Tools::UpdateProtectedPaths, server_context: { workspace: @workspace, principal: principal }, args: args)
  end
end
