require "test_helper"

# Saving an account checks its address the way every call to it is checked, so what saves is what Halon can reach.
class WorkspaceAiAccountServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    on_firefights_cloud!
    FirefightAi.stubs(:check_account).returns(nil)
  end

  test "an address whose name does not resolve is refused when saved" do
    Addrinfo.stubs(:getaddrinfo).with("llm.nowhere.example", nil, nil, :STREAM).raises(SocketError, "getaddrinfo failed")

    error = assert_raises(ActiveRecord::RecordInvalid) { save_with("https://llm.nowhere.example/v1") }
    assert_includes error.record.errors[:base], "llm.nowhere.example could not be found."
  end

  test "a name that resolves inside the network is refused, unless whoever runs Firefight allowed it" do
    Addrinfo.stubs(:getaddrinfo).with("llm.corp.example", nil, nil, :STREAM).returns([ Addrinfo.tcp("10.0.0.7", 443) ])

    error = assert_raises(ActiveRecord::RecordInvalid) { save_with("https://llm.corp.example/v1") }
    assert_includes error.record.errors[:base], "llm.corp.example is on a private network, which Firefight does not connect to."

    ENV.stubs(:fetch).with("INTEGRATION_AI_ACCOUNT_PRIVATE_HOSTS", "").returns("llm.corp.example")
    assert save_with("https://llm.corp.example/v1").account.persisted?
  end

  private

  def save_with(address)
    WorkspaceAiAccountService.new(@workspace).create!(provider: "openai", label: "Proxy", settings: { "api_key" => "sk-own", "api_base" => address },
                                                      models: { "main" => "gpt-4o", "fast" => "gpt-4o-mini" })
  end
end
