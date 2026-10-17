require "test_helper"

module Mcp
  module Tools
    class PageOnCallTest < ActiveSupport::TestCase
      include PagingTestHelper

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @incident = incidents(:active_critical_ws1)
        @bob = workspace_memberships(:bob_workspace_one)
        @context = { workspace: @workspace, principal: @bob }
        @pagerduty = connect_pagerduty!(@workspace)
      end

      def call(args) = ToolDispatcher.call(tool: PageOnCall, server_context: @context, args: args)

      test "a member raises a page through the connected tool, with Halon's chat offered it beside escalating" do
        group = Chat::Tools::Groups::FIREFIGHT.find { |each| each.tools.include?(FirefightTools::PAGE_ON_CALL) }
        assert_equal Chat::Tools::Groups::INCIDENT_RESPONSE, group.key
        Integrations::PagerdutyApi.any_instance.stubs(:services).returns([ { "id" => "PF9KMXH", "name" => "Checkout" } ])
        Integrations::PagerdutyApi.any_instance.stubs(:create_incident).returns(pagerduty_incident)

        answer = call({ incident: @incident.identifier, target: "Checkout", reason: "Checkout returns 500 since 03:02", person: "bob@example.com" }).structured_content

        assert_equal [ "PagerDuty", "Checkout", Incident::Page::STATE_TRIGGERED, "#42" ], answer.values_at(:tool, :target, :state, :page)
        page = @incident.pages.sole
        assert_equal [ @bob, @bob ], [ page.requested_by, page.paged_member ]
        assert_equal @bob, @incident.incident_events.find_by!(event_type: IncidentEvent::PAGE_RAISED).actor
      end

      test "each tool says what a page goes to, and with several tools the call names one" do
        connect_opsgenie!(@workspace)
        target = PageOnCall.schema_for(@workspace).dig(:properties, :target, :description)
        assert_match "pagerduty: a PagerDuty service", target
        assert_match "opsgenie: an Opsgenie team", target

        refused = call({ incident: @incident.identifier, target: "Checkout", reason: "Down" })
        assert refused.error?
        assert_match "Name the on-call tool in tool, one of pagerduty, opsgenie.", refused.content.first[:text]
      end

      test "an incident that is over is not paged for, and with no on-call tool the call says to connect one" do
        @incident.update_columns(incident_status_id: @workspace.default_closed_status.id)
        over = call({ incident: @incident.identifier, target: "Checkout", reason: "Down" })
        assert over.error?
        assert_match "nobody can be paged for it", over.content.first[:text]

        @pagerduty.update!(deleted_at: Time.current)
        none = call({ incident: incidents(:active_major_ws1).identifier, target: "Checkout", reason: "Down" })
        assert_match "Connect an on-call tool under Integrations", none.content.first[:text]
        assert_empty Incident::Page.where(workspace: @workspace)
      end
    end
  end
end
