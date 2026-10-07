require "test_helper"

# A workspace's AI account with its own API base, on a build that refuses private networks, resolves and checks the
# address again before every call and connects to the address it checked, so DNS rebinding cannot reach inside.
class Integrations::PublicAddressAdapterTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "an account with its own address calls through the checking adapter only where private networks are refused" do
    account = add_ai_account!(@workspace, provider: "openai", key: "sk-own", settings: { "api_base" => "https://llm.example.com/v1" })
    assert_not_equal WorkspaceAiAccount::PUBLIC_ADDRESS_ADAPTER, account.llm_context.config.faraday_adapter, "a self-hosted install reaches its own network"

    on_firefights_cloud!
    assert_equal WorkspaceAiAccount::PUBLIC_ADDRESS_ADAPTER, account.reload.llm_context.config.faraday_adapter
    assert_not_equal WorkspaceAiAccount::PUBLIC_ADDRESS_ADAPTER, add_ai_account!(@workspace, label: "Default address").llm_context.config.faraday_adapter
  end

  test "a name that now resolves to a private, loopback, link-local or metadata address is refused before the request" do
    %w[10.0.0.5 127.0.0.1 169.254.169.254 fd00::1].each do |address|
      resolve("llm.example.com", to: address)

      error = assert_raises(Faraday::ConnectionFailed) { connection.get("/v1/models") }
      assert_match "private network", error.message
    end
  end

  test "a public answer is connected to by the address checked, never resolved a second time" do
    resolve("llm.example.com", to: "93.184.216.34")
    adapter = Integrations::PublicAddressAdapter.new
    env = { url: URI("https://llm.example.com/v1/models"), request: {} }

    assert_equal [ "llm.example.com", "93.184.216.34" ], adapter.net_http_connection(env).then { |http| [ http.address, http.ipaddr ] }
  end

  test "the code fix proxy checks the paying account's own address before every call" do
    on_firefights_cloud!
    add_ai_account!(@workspace, settings: { "api_base" => "https://llm.example.com/v1" })
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace), repository: "acme/api")
    resolve("llm.example.com", to: "10.0.0.5")
    Net::HTTP.expects(:start).never

    error = assert_raises(FirefightAi::ModelProxy::Refused) do
      CodeAgent::Relay.new(session).forward(path: "messages", body: "{}", headers: {}) { |*| nil }
    end
    assert_match "private network", error.message
  end

  private

  def connection = Faraday.new("https://llm.example.com") { |faraday| faraday.adapter WorkspaceAiAccount::PUBLIC_ADDRESS_ADAPTER }

  def resolve(host, to:)
    Addrinfo.stubs(:getaddrinfo).with(host, nil, nil, :STREAM).returns([ Addrinfo.tcp(to, 443) ])
  end
end
