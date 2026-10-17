require "test_helper"

module Mcp
  module Tools
    # What Halon may do without asking, over MCP: read by an admin's token, and changed only in Halon's chat for the person
    # who confirmed it on its card.
    class AllowanceToolsTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
        @merge = github.tools.create!(name: "merge_pull_request", description: "Merge", enabled: true, read_only: false, params_schema: {})
      end

      def call(tool, args) = ToolDispatcher.run(tool: tool, workspace: @workspace, principal: @admin, args: args)

      test "they sit with permissions, always ask a person in a chat, and read, write and delete as the screen does" do
        group = Chat::Tools::Groups::FIREFIGHT.find { |each| each.tools.include?(FirefightTools::UPSERT_ALLOWANCE) }
        assert_equal Chat::Tools::Groups::PERMISSIONS, group.key
        assert UpsertAllowance.asks_a_person?
        assert DeleteAllowance.asks_a_person?
        assert_equal [ Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE ], UpsertAllowance.authorization(@workspace, {})

        created = call(UpsertAllowance, { action_key: @merge.action_key, environment: "Production" }).structured_content
        assert_equal [ "Merge pull request on GitHub in Production", @admin.display_name ], [ created[:sentence], created[:created_by] ]

        call(UpsertAllowance, { id: created[:id], enabled: false })
        listed = call(ListAllowances, {}).structured_content
        assert_equal [ [ created[:id], false ] ], listed[:allowances].map { |entry| [ entry[:id], entry[:enabled] ] }
        assert listed[:safe_changes_without_asking]

        assert call(DeleteAllowance, { id: created[:id] }).structured_content[:deleted]
        assert_not Ability::Allowance.exists?(created[:id])
      end

      test "a token reads the list and is refused every change, and an access change is refused with why" do
        context = { workspace: @workspace, principal: @admin }
        assert_not ToolDispatcher.call(tool: ListAllowances, server_context: context, args: {}).error?

        refused = ToolDispatcher.call(tool: UpsertAllowance, server_context: context, args: { capability: "rollback" })
        assert refused.error?
        assert_equal Ability::Allowance::TOKEN_CHANGE_REFUSAL, refused.content.sole[:text]
        assert_empty @workspace.allowances

        secret = @merge.integration.tools.create!(name: "set_actions_secret", description: "Set", enabled: true, read_only: false, params_schema: {})
        invalid = call(UpsertAllowance, { action_key: secret.action_key })
        assert invalid.error?
        assert_match "a person is always asked", invalid.content.sole[:text]
      end
    end
  end
end
