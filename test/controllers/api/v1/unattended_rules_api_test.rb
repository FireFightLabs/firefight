require "test_helper"

class Api::V1::UnattendedRulesApiTest < ActionDispatch::IntegrationTest
  include OnCallTestHelper

  setup do
    alert_run_with_restart_fix
    @admin = workspace_memberships(:alice_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Alice personal")
    @bob = workspace_memberships(:bob_workspace_one)
    _, @member_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @bob, on_behalf_of: @bob, name: "Bob personal")
  end

  def send_json(verb, path, body = {}, token: @admin_token)
    public_send(verb, path, params: body.to_json, headers: api_headers(token: token))
  end

  test "an admin reads the rules, and every change with a token is refused with why, a member's included" do
    used = restart_rule

    get "/api/v1/unattended_rules", headers: api_headers(token: @admin_token)
    assert_equal [ used.id ], json_response["unattended_rules"].map { |rule| rule["id"] }

    send_json(:post, "/api/v1/unattended_rules", { capability: "restart", resource: "web", metric: "http_5xx", threshold: 50, minutes: 10 })
    assert_response :unprocessable_entity
    assert_equal Ability::UnattendedRule::TOKEN_CHANGE_REFUSAL, json_response.dig("error", "message")

    send_json(:patch, "/api/v1/unattended_rules/#{used.id}", { enabled: false })
    assert_response :unprocessable_entity
    assert used.reload.enabled?

    send_json(:delete, "/api/v1/unattended_rules/#{used.id}", {}, token: @member_token)
    assert_response :unprocessable_entity
    assert Ability::UnattendedRule.exists?(used.id)
  end
end
