require "test_helper"

# The ChatGPT sign in seam: a plain PKCE flow whose addresses all come from the environment.
class AiAccountSignInTest < ActiveSupport::TestCase
  ENVIRONMENT = {
    "CHATGPT_OAUTH_CLIENT_ID" => "firefight-client", "CHATGPT_OAUTH_AUTHORIZE_URL" => "https://auth.example.com/authorize",
    "CHATGPT_OAUTH_TOKEN_URL" => "https://auth.example.com/token", "CHATGPT_OAUTH_SCOPES" => "openid email",
    "CHATGPT_API_BASE" => "https://api.example.com/v1"
  }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    ENV.stubs(:[]).returns(nil)
    ENVIRONMENT.each { |name, value| ENV.stubs(:[]).with(name).returns(value) }
  end

  test "it is not available until its flag is on" do
    assert_raises(AiAccountSignIn::Failed) { AiAccountSignIn.new(@workspace).begin(redirect_uri: "https://ff.example.com/callback") }
  end

  test "signing in sends a code challenge, keeps only the state and verifier, and saves the tokens as the account's credentials" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN)
    flow = AiAccountSignIn.new(@workspace).begin(redirect_uri: "https://ff.example.com/callback")
    query = Rack::Utils.parse_query(URI.parse(flow[:url]).query)
    assert_equal [ "firefight-client", "S256", "openid email" ], query.values_at("client_id", "code_challenge_method", "scope")
    assert_equal %w[provider state verifier], flow[:pending].keys.sort

    id_token = "x.#{Base64.urlsafe_encode64({ email: 'ana@acme.test' }.to_json, padding: false)}.y"
    token = Net::HTTPOK.new("1.1", "200", "OK")
    token.stubs(:body).returns({ access_token: "chatgpt-access", refresh_token: "chatgpt-refresh", expires_in: 3600, id_token: id_token }.to_json)
    Net::HTTP.stubs(:start).returns(token)
    FirefightAi.stubs(:check_account).returns(nil)
    # The test registry holds a few older models, and the account starts on the recommended ones.
    FirefightAi.stubs(:context_window).returns(400_000)

    result = AiAccountSignIn.new(@workspace).finish!(flow[:pending], code: "the-code", state: flow[:pending]["state"],
                                                     redirect_uri: "https://ff.example.com/callback")

    account = result.account
    assert_equal [ AiProviders::KIND_OAUTH, "Signed in as ana@acme.test." ], [ account.kind, account.credential_summary ]
    config = account.llm_context.config
    assert_equal [ "chatgpt-access", "https://api.example.com/v1" ], [ config.openai_api_key, config.openai_api_base ]
  end

  test "a callback whose state does not match is refused" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN)

    assert_raises(AiAccountSignIn::Failed) do
      AiAccountSignIn.new(@workspace).finish!({ "provider" => "openai", "state" => "a", "verifier" => "v" }, code: "c", state: "b", redirect_uri: "x")
    end
  end
end
