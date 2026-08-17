require "test_helper"

module Integrations
  class HealthCheckSweepJobTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    setup do
      @integration = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP,
        provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.example/mcp" }
      )
      @row = @integration.integration_environments.create!(
        health_status: IntegrationEnvironment::HEALTH_HEALTHY
      )
    end

    test "sweeps enabled rows and records the new health state" do
      McpClient.any_instance.stubs(:ping).raises(McpClient::Error, "token revoked")

      HealthCheckSweepJob.perform_now

      assert_equal IntegrationEnvironment::HEALTH_FAILING, @row.reload.health_status
      assert_equal "token revoked", @row.health_error
    end

    test "skips disabled integrations and disabled rows" do
      @integration.update!(disabled_at: Time.current)
      McpClient.any_instance.expects(:ping).never

      HealthCheckSweepJob.perform_now

      assert_equal IntegrationEnvironment::HEALTH_HEALTHY, @row.reload.health_status
    end
  end
end
