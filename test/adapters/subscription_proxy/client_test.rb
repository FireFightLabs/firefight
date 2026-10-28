require "test_helper"

class SubscriptionProxy::ClientTest < ActiveSupport::TestCase
  setup do
    configure_subscription_proxy!
    @workspace = workspaces(:slack_workspace_one)
  end

  test "an unconfigured proxy is refused before any call" do
    SubscriptionProxy.unstub(:settings)

    assert_raises(SubscriptionProxy::NotConfigured) { SubscriptionProxy::Client.new }
  end

  test "a device sign-in answers its code, where to enter it and when the proxy stops waiting" do
    sent = stub_proxy(proxy_response(200, { status: "ok", state: "xai-1", url: "https://accounts.x.ai/oauth2/device?user_code=SP7R", user_code: "SP7R", flow: "device", expires_in: 1800 }))

    sign_in_id = SecureRandom.uuid
    sign_in = SubscriptionProxy::Client.new(workspace: @workspace).start_sign_in("xai", sign_in_id: sign_in_id)

    assert_predicate sign_in, :device?
    assert_equal [ "xai-1", "SP7R" ], [ sign_in.state, sign_in.user_code ]
    assert_in_delta 30.minutes.from_now, sign_in.expires_at, 5
    asked = Rack::Utils.parse_query(URI(sent.first.path).query)
    assert_equal({ "provider" => "xai", "firefight_sign_in" => sign_in_id, "firefight_workspace" => @workspace.id }, asked,
                 "the proxy stamps the credential with the sign-in and its workspace")
    assert_equal "Bearer management-key", sent.first["Authorization"]
  end

  test "a browser sign-in has no code, and the address the person lands on is handed back by its state and code" do
    sent = stub_proxy(proxy_response(200, { status: "ok", state: "abc", url: "https://auth.openai.com/oauth/authorize?state=abc" }), proxy_response(200, { status: "ok" }))
    client = SubscriptionProxy::Client.new(workspace: @workspace)

    refute_predicate client.start_sign_in("codex", sign_in_id: SecureRandom.uuid), :device?
    client.finish_sign_in("codex", state: "abc", code: "the-code")

    assert_equal "/v8/management/oauth/callback", sent.last.path
    assert_equal({ "provider" => "codex", "state" => "abc", "code" => "the-code" }, JSON.parse(sent.last.body))
  end

  test "a sign-in's state reads as waiting, done or the proxy's reason, and a missing state is never asked about" do
    stub_proxy(proxy_response(200, { status: "wait" }), proxy_response(200, { status: "ok" }), proxy_response(200, { status: "error", error: "Authentication failed" }))
    client = SubscriptionProxy::Client.new

    assert_equal [ :waiting, :done, "Authentication failed" ], 3.times.map { client.sign_in_status("s") }
    assert_raises(ArgumentError) { client.sign_in_status("") }
  end

  test "credentials are read by name with their state and limits, and no token" do
    stub_proxy(proxy_response(200, { files: [ {
      name: "codex-a@example.com-plus.json", provider: "codex", email: "a@example.com", status: "active", unavailable: false,
      quota: { observed_at: "2026-10-28T10:00:00Z", signals: { "x-codex-primary-used-percent" => "40" } },
      created_at: "2026-10-28T09:00:00Z", success: 3, failed: 1, note: "9f1c2e60-0000-4000-8000-000000000001"
    } ] }))

    credential = SubscriptionProxy::Client.new.credentials.sole

    assert_equal [ "codex-a@example.com-plus.json", "codex", "a@example.com", 3, 1 ], [ credential.name, credential.provider, credential.email, credential.succeeded, credential.failed ]
    assert_equal "9f1c2e60-0000-4000-8000-000000000001", credential.sign_in_id
    assert_equal({ "x-codex-primary-used-percent" => "40" }, credential.quota)
    assert_equal Time.zone.parse("2026-10-28T09:00:00Z"), credential.created_at
  end

  test "the proxy says which credential a sign-in made and whose it is, or why it refused it" do
    sent = stub_proxy(proxy_response(200, { refused: "taken", credential: "", workspace: "" }),
                      proxy_response(200, { refused: "", credential: "codex-ana.json", workspace: @workspace.id }))
    client = SubscriptionProxy::Client.new(workspace: @workspace)

    refused = client.sign_in_result("9f1c2e60-0000-4000-8000-000000000001")
    made = client.sign_in_result("9f1c2e60-0000-4000-8000-000000000002")

    assert_equal [ SubscriptionProxy::Client::REFUSED_TAKEN, nil ], [ refused.refused, refused.credential ]
    assert_equal [ nil, "codex-ana.json", @workspace.id ], [ made.refused, made.credential, made.workspace ]
    assert_equal [ "/firefight/sign-ins/9f1c2e60-0000-4000-8000-000000000001", "Bearer management-key" ], [ sent.first.path, sent.first["Authorization"] ]
  end

  test "a delete can only ever name one credential" do
    sent = stub_proxy(proxy_response(200, { status: "ok" }))
    client = SubscriptionProxy::Client.new(workspace: @workspace)

    client.delete("codex-a.json")

    assert_equal "/v8/management/credentials?name=codex-a.json", sent.last.path
    [ "", "*", "all", "../config.json" ].each do |name|
      assert_raises(ArgumentError) { client.delete(name) }
    end
  end

  test "deleting a credential the proxy no longer holds is done, and is not kept as a failure" do
    stub_proxy(proxy_response(404, { error: "auth file not found" }))

    assert_nil SubscriptionProxy::Client.new(workspace: @workspace).delete("codex-gone.json")
    assert_not PlatformCallFailure.exists?(workspace: @workspace, platform: SubscriptionProxy::PLATFORM)
  end

  test "changing a credential the proxy no longer holds says it is not found" do
    stub_proxy(proxy_response(404, { error: "auth file not found" }))

    error = assert_raises(SubscriptionProxy::NotFound) { SubscriptionProxy::Client.new(workspace: @workspace).prioritize("codex-gone.json", 1) }
    assert_equal 404, error.status
  end

  test "a workspace sees only the models its own prefix names that answer in text, with their sizes" do
    other = workspaces(:slack_workspace_two)
    sized = { data: [
      { id: "#{@workspace.id}/gpt-6-sol", display_name: "GPT 6.0 Sol", max_input_tokens: 272_000, max_tokens: 128_000 },
      { id: "#{@workspace.id}/gpt-image-2", display_name: "GPT Image 2", max_input_tokens: 200_000, max_tokens: 64_000 },
      { id: "#{other.id}/grok-4.7", display_name: "Grok 4.7", max_input_tokens: 500_000, max_tokens: 500_000 }
    ] }
    shapes = { models: [
      { name: "models/#{@workspace.id}/gpt-6-sol", supportedInputModalities: %w[text image], supportedOutputModalities: %w[text] },
      { name: "models/#{@workspace.id}/gpt-image-2" },
      { name: "models/grok-4.7", supportedInputModalities: %w[text], supportedOutputModalities: %w[text] }
    ] }
    sent = stub_proxy(proxy_response(200, sized), proxy_response(200, shapes))

    models = SubscriptionProxy::Client.new.models_for(@workspace)

    assert_equal [ SubscriptionProxy::Client::Model.new(id: "gpt-6-sol", name: "GPT 6.0 Sol", context_window: 272_000, max_output_tokens: 128_000, input_modalities: %w[text image]) ], models
    assert_equal "client-key", sent.first["x-api-key"]
    assert_nil sent.first["Authorization"], "the model list never carries the management key"
  end

  test "a failed call is kept for its workspace and raised as the proxy's own error" do
    stub_proxy(proxy_response(500, { error: "core auth manager unavailable" }))

    error = assert_raises(SubscriptionProxy::Refused) { SubscriptionProxy::Client.new(workspace: @workspace).credentials }

    assert_equal 500, error.status
    failure = PlatformCallFailure.find_by!(workspace: @workspace, platform: SubscriptionProxy::PLATFORM)
    assert_equal [ "credentials", "SubscriptionProxy::Refused" ], [ failure.operation, failure.error_class ]
    assert_match "core auth manager unavailable", failure.message
  end

  test "a proxy that cannot be reached is unreachable" do
    Net::HTTP.stubs(:start).raises(Errno::ECONNREFUSED)

    assert_raises(SubscriptionProxy::Unreachable) { SubscriptionProxy::Client.new(workspace: @workspace).health }
    assert PlatformCallFailure.exists?(workspace: @workspace, platform: SubscriptionProxy::PLATFORM, operation: "health")
  end
end
