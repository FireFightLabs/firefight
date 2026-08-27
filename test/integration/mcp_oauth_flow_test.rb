require "test_helper"

class McpOauthFlowTest < ActionDispatch::IntegrationTest
  include OmniauthTestHelper


  REDIRECT_URI = "http://localhost:33418/callback".freeze

  setup do
    OmniAuth.config.test_mode = true
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @verifier = SecureRandom.urlsafe_base64(48)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
  end

  teardown do
    OmniAuth.config.mock_auth[:slack_openid] = nil
    OmniAuth.config.test_mode = false
  end

  def sign_in_alice
    sign_in(@membership)
  end

  def sign_in(membership)
    OmniAuth.config.mock_auth[:slack_openid] = mock_slack_openid_auth_hash(
      uid: membership.platform_user_id,
      info: { name: membership.user.name, email: membership.user.email,
              team_id: membership.workspace.platform_id, team_name: membership.workspace.name }
    )
    get "/auth/slack_openid/callback"
  end

  def granted_membership_id(client_id, params)
    post oauth_authorization_path, params: params
    code = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
    post oauth_token_path, params: {
      grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI,
      client_id: client_id, code_verifier: @verifier
    }
    Doorkeeper::AccessToken.by_token(JSON.parse(response.body).fetch("access_token")).resource_owner_id
  end

  def register_client
    post oauth_register_path, params: { client_name: "Claude Code", redirect_uris: [ REDIRECT_URI ] }, as: :json
    assert_response :created
    JSON.parse(response.body).fetch("client_id")
  end

  def authorize_params(client_id)
    {
      client_id: client_id, redirect_uri: REDIRECT_URI, response_type: "code",
      state: "xyz", code_challenge: @challenge, code_challenge_method: "S256"
    }
  end

  test "discovery metadata points clients at the authorization server" do
    get "/.well-known/oauth-protected-resource"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal mcp_url, body["resource"]

    get "/.well-known/oauth-authorization-server"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal oauth_register_url, body["registration_endpoint"]
    assert_equal [ "S256" ], body["code_challenge_methods_supported"]
    assert_equal [ "none" ], body["token_endpoint_auth_methods_supported"]
  end

  test "the full connect flow: register, consent, token exchange, MCP call, revoke" do
    client_id = register_client
    sign_in_alice

    # Consent screen renders for the signed-in member
    get oauth_authorization_path(authorize_params(client_id))
    assert_response :success
    assert_includes response.body, "Claude Code"

    # Authorize → redirect back to the client with a code
    post oauth_authorization_path, params: authorize_params(client_id)
    assert_response :redirect
    code = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")

    # Public-client token exchange with the PKCE verifier
    post oauth_token_path, params: {
      grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI,
      client_id: client_id, code_verifier: @verifier
    }
    assert_response :success
    token_body = JSON.parse(response.body)
    access_token = token_body.fetch("access_token")
    refresh_token = token_body.fetch("refresh_token")
    assert_equal "mcp:read", token_body["scope"]

    # The token works against MCP as the consenting member
    post mcp_path,
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: Mcp::Tools::SEARCH_INCIDENTS, arguments: { limit: 1 } } }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{access_token}" }
    assert_response :success
    result = JSON.parse(response.body).fetch("result")
    assert_not result["isError"]
    assert result.dig("structuredContent", "incidents").any?

    # Refresh rotates the token
    post oauth_token_path, params: { grant_type: "refresh_token", refresh_token: refresh_token, client_id: client_id }
    assert_response :success
    rotated = JSON.parse(response.body).fetch("access_token")
    assert_not_equal access_token, rotated

    # It shows under connected agents, and revoking kills access on the next call
    get developer_api_keys_url, headers: { "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version }
    agents = JSON.parse(response.body).dig("props", "connectedAgents")
    assert_equal [ "Claude Code" ], agents.map { |a| a["name"] }

    delete connected_agent_url(agents.first["id"])

    post mcp_path,
         params: { jsonrpc: "2.0", id: 2, method: "ping" }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{rotated}" }
    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], "resource_metadata"
  end

  test "the token exchange fails with a wrong PKCE verifier" do
    client_id = register_client
    sign_in_alice
    post oauth_authorization_path, params: authorize_params(client_id)
    code = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")

    post oauth_token_path, params: {
      grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI,
      client_id: client_id, code_verifier: "wrong-verifier"
    }

    assert_response :bad_request
  end

  test "authorization without PKCE is rejected" do
    client_id = register_client
    sign_in_alice

    get oauth_authorization_path(client_id: client_id, redirect_uri: REDIRECT_URI, response_type: "code", state: "s")

    assert_response :bad_request
  end

  test "the consent screen names the one workspace a member belongs to" do
    client_id = register_client
    sign_in(workspace_memberships(:bob_workspace_one))

    get oauth_authorization_path(authorize_params(client_id))

    assert_response :success
    assert_select "p.subject", text: /#{@workspace.name}.*Bob Jones/
    assert_select "select[name=workspace_id]", false
  end

  test "a member of several workspaces picks which one the agent reaches" do
    client_id = register_client
    sign_in_alice

    get oauth_authorization_path(authorize_params(client_id))

    assert_response :success
    assert_select "select[name=workspace_id] option", 2
    assert_select "select[name=workspace_id] option[selected][value=?]", @workspace.id, text: @workspace.name
    assert_select "select[name=workspace_id] option[value=?]", workspaces(:slack_workspace_two).id
  end

  test "the token is bound to the picked workspace, not the session's" do
    client_id = register_client
    sign_in_alice
    picked = workspace_memberships(:alice_workspace_two)

    granted = granted_membership_id(client_id, authorize_params(client_id).merge(workspace_id: picked.workspace_id))

    assert_equal picked.id, granted
  end

  test "a workspace the member does not belong to cannot be granted" do
    client_id = register_client
    sign_in_alice
    outsider = workspaces(:slack_workspace_expired)

    granted = granted_membership_id(client_id, authorize_params(client_id).merge(workspace_id: outsider.id))

    assert_equal @membership.id, granted
  end

  test "the consent screen requires a session" do
    client_id = register_client

    get oauth_authorization_path(authorize_params(client_id))

    assert_redirected_to login_path
  end

  # Rails.env.local? is true under test, so the SSL rule never fires here.
  # Call it the way production would to prove loopback clients still register.
  test "a loopback redirect URI is exempt from the HTTPS requirement" do
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))
    forces_ssl = Doorkeeper.config.force_ssl_in_redirect_uri

    assert_not forces_ssl.call(URI("http://localhost:33418/callback"))
    assert_not forces_ssl.call(URI("http://127.0.0.1:33418/callback"))
    assert_not forces_ssl.call(URI("http://[::1]:33418/callback"))
    assert forces_ssl.call(URI("http://claude.localhost.example.com/callback"))
  end

  # The registration rate limit itself relies on Rails' rate_limit + the
  # production cache store. The null store in test can't exercise it.
  test "registration rejects invalid client metadata" do
    post oauth_register_path, params: { client_name: "Bad", redirect_uris: [] }, as: :json

    assert_response :bad_request
    assert_equal "invalid_client_metadata", JSON.parse(response.body)["error"]
  end
end
