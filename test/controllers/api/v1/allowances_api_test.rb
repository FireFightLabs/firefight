require "test_helper"

# A token reads what Halon may do without asking and changes none of it, an admin's included.
class Api::V1::AllowancesApiTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(workspace: @workspace, created_by: @admin, on_behalf_of: @admin, name: "Alice personal")
    bob = workspace_memberships(:bob_workspace_one)
    _, @member_token = ApiKey.create_with_token!(workspace: @workspace, created_by: bob, on_behalf_of: bob, name: "Bob personal")
  end

  def send_json(verb, path, body = {}, token: @admin_token)
    public_send(verb, path, params: body.to_json, headers: api_headers(token: token))
  end

  test "an admin reads the list, and every change with a token is refused with why" do
    entry = @workspace.allowances.create!(capability: Integrations::Capabilities::ROLLBACK, environment: catalog_entries(:production_env))

    get "/api/v1/allowances", headers: api_headers(token: @admin_token)
    assert_response :success
    assert_equal [ [ entry.id, "Roll back deploys in Production" ] ], json_response["allowances"].map { |each| [ each["id"], each["sentence"] ] }

    send_json(:post, "/api/v1/allowances", { capability: "restart" })
    assert_response :unprocessable_entity
    assert_equal Ability::Allowance::TOKEN_CHANGE_REFUSAL, json_response.dig("error", "message")

    send_json(:patch, "/api/v1/allowances/#{entry.id}", { enabled: false })
    assert_response :unprocessable_entity
    assert entry.reload.enabled?

    send_json(:delete, "/api/v1/allowances/#{entry.id}", {}, token: @member_token)
    assert_response :unprocessable_entity
    assert Ability::Allowance.exists?(entry.id)
  end

  test "a member may not read it" do
    get "/api/v1/allowances", headers: api_headers(token: @member_token)

    assert_response :forbidden
  end
end
