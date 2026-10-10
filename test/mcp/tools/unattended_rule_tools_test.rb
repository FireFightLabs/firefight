require "test_helper"

module Mcp
  module Tools
    class UnattendedRuleToolsTest < ActiveSupport::TestCase
      include OnCallTestHelper

      setup do
        alert_run_with_restart_fix
        @admin = workspace_memberships(:alice_workspace_one)
        @context = { workspace: @workspace, principal: @admin }
      end

      def call(tool, args) = ToolDispatcher.call(tool: tool, server_context: @context, args: args)

      test "they sit with permissions, authorize as permissions and read, write and delete as the screen does" do
        group = Chat::Tools::Groups::FIREFIGHT.find { |each| each.tools.include?(UPSERT_UNATTENDED_RULE) }
        assert_equal Chat::Tools::Groups::PERMISSIONS, group.key
        assert_includes group.tools, LIST_UNATTENDED_RULES
        assert_includes group.tools, DELETE_UNATTENDED_RULE
        assert_equal [ Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE ], UpsertUnattendedRule.authorization(@workspace, {})

        created = call(UpsertUnattendedRule, { capability: "restart", resource: "web", metric: "http_5xx", threshold: 50 }).structured_content
        assert_equal [ "web", 10, @admin.display_name ], [ created.dig(:resource, :name), created[:minutes], created[:created_by] ]
        assert_match "holds no grant", created[:blocked_reason]

        call(UpsertUnattendedRule, { id: created[:id], enabled: false })
        listed = call(ListUnattendedRules, {}).structured_content[:unattended_rules]
        assert_equal [ [ created[:id], false ] ], listed.map { |rule| [ rule[:id], rule[:enabled] ] }

        assert call(DeleteUnattendedRule, { id: created[:id] }).structured_content[:deleted]
        assert_not Ability::UnattendedRule.exists?(created[:id])
      end

      test "a rule Halon acted under is refused deletion with why, and a bad rule says what is wrong" do
        used = restart_rule
        @plan.steps.sole.update!(applied_under_rule: used)

        refused = call(DeleteUnattendedRule, { id: used.id })
        assert refused.error?
        assert_match "stays for the record", refused.content.sole[:text]

        invalid = call(UpsertUnattendedRule, { capability: "restart", resource: "nowhere", metric: "cpu", threshold: 1 })
        assert invalid.error?
        assert_match "Resource must exist", invalid.content.sole[:text]
      end

      test "a member may not reach them" do
        refused = ToolDispatcher.call(tool: ListUnattendedRules, server_context: { workspace: @workspace, principal: workspace_memberships(:bob_workspace_one) }, args: {})

        assert refused.error?
      end
    end
  end
end
