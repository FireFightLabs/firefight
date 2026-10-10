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

  test "an admin creates a rule naming a resource by name, reads it back, and turns it off with enabled alone" do
    send_json(:post, "/api/v1/unattended_rules", { capability: "restart", resource: "web", metric: "http_5xx", threshold: 50, minutes: 10 })

    assert_response :created
    assert_equal [ "Restart web when the average of its 5xx responses over the last 10 minutes is above 50.", @web.id, "Alice Smith" ],
                 [ json_response["sentence"], json_response.dig("resource", "id"), json_response["created_by"] ]
    id = json_response["id"]

    send_json(:patch, "/api/v1/unattended_rules/#{id}", { enabled: false })
    assert_response :ok
    assert_equal [ false, 50.0 ], [ json_response["enabled"], json_response["threshold"] ]

    get "/api/v1/unattended_rules", headers: api_headers(token: @admin_token)
    assert_equal [ id ], json_response["unattended_rules"].map { |rule| rule["id"] }
  end

  test "a rule Halon acted under cannot be deleted, and one it never acted under can" do
    used = restart_rule
    @plan.steps.sole.update!(applied_under_rule: used)
    unused = restart_rule(metric: "cpu")

    send_json(:delete, "/api/v1/unattended_rules/#{used.id}")
    assert_response :unprocessable_entity
    assert_match "stays for the record", json_response.dig("error", "message")

    send_json(:delete, "/api/v1/unattended_rules/#{unused.id}")
    assert_response :no_content
  end

  test "a member's token is refused and a resource off the map is invalid" do
    send_json(:post, "/api/v1/unattended_rules", { capability: "restart", resource: "web", metric: "cpu", threshold: 1 }, token: @member_token)
    assert_response :forbidden

    send_json(:post, "/api/v1/unattended_rules", { capability: "restart", resource: "nothing-here", metric: "cpu", threshold: 1 })
    assert_response :unprocessable_entity
    assert_empty @workspace.unattended_rules
  end
end
