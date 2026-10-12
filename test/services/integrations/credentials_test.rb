require "test_helper"

module Integrations
  class CredentialsTest < ActiveSupport::TestCase
    setup do
      integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana",
                                                                          settings: { "server_url" => "https://mcp.grafana.com/mcp/mystack.grafana.net" })
      @row = integration.integration_environments.create!
      @row.store_oauth!("access_token" => "stale", "refresh_token" => "rt-1", "expires_at" => 1.minute.ago.iso8601,
                        "token_endpoint" => "https://mcp.grafana.com/mcp/oauth/token", "client_id" => "cid")
    end

    test "a token another caller refreshed meanwhile is used as it is, so a refresh token the provider rotates is spent only once" do
      stale = IntegrationEnvironment.find(@row.id)
      @row.rotate_oauth!(@row.oauth.merge("access_token" => "fresh", "refresh_token" => "rt-2", "expires_at" => 1.hour.from_now.iso8601))
      OauthClient.expects(:refresh).never

      assert_equal "Bearer fresh", Credentials.headers_for(stale)["Authorization"]
    end

    test "a refresh token the provider no longer takes says how to sign in again, and keeps the credentials as they were" do
      OauthClient.stubs(:refresh).raises(OauthClient::SignInEnded, "refresh token expired")

      error = assert_raises(OauthClient::SignInEnded) { Credentials.headers_for(@row) }

      assert_equal "The sign-in to Grafana has ended, so Firefight can no longer reach it. Open its details, choose Add connection and sign in again " \
                   "under the name Grafana.", error.message
      assert_equal "rt-1", @row.reload.oauth["refresh_token"]
    end
  end
end
