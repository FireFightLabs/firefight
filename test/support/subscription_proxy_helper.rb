# The subscription proxy as tests see it: configured with made-up keys, and answering through a stubbed transport.
module SubscriptionProxyHelper
  PROXY_URL = "http://subscription-proxy.internal:8317".freeze

  def configure_subscription_proxy!
    SubscriptionProxy.stubs(:settings).returns(
      ActiveSupport::OrderedOptions.new.merge!(url: PROXY_URL, client_key: "client-key", management_key: "management-key")
    )
  end

  # Configured, and its last check passed, so subscriptions are offered and used.
  def subscription_proxy_up!
    configure_subscription_proxy!
    SubscriptionProxy::Check.passed!(version: "v8.0.28")
  end

  SUBSCRIPTION_MODELS = [
    { "id" => "gpt-6.1-sol", "name" => "GPT 6.1 Sol", "context_window" => 272_000, "max_output_tokens" => 128_000, "input_modalities" => %w[text image] },
    { "id" => "gpt-6-luna", "name" => "GPT 6.0 Luna", "context_window" => 272_000, "max_output_tokens" => 128_000, "input_modalities" => %w[text] }
  ].freeze

  # A subscription account as a finished sign-in leaves it, without asking the proxy.
  def add_subscription_account!(workspace, subscription: "chatgpt", credential: "codex-#{SecureRandom.hex(3)}.json", email: "ana@example.com",
                                models: SUBSCRIPTION_MODELS, state: {})
    WorkspaceAiAccount.create_in_order!(workspace, kind: AiProviders::KIND_SUBSCRIPTION, provider: subscription, label: "ChatGPT, #{email}",
                                                   proxy_credential: credential, credential_hint: email,
                                                   proxy_state: { "models" => models, "proxy" => "codex" }.merge(state))
  end

  def proxy_credential(name:, provider: "codex", email: "ana@example.com", created_at: Time.current, updated_at: created_at, **rest)
    SubscriptionProxy::Client::Credential.new(
      name: name, provider: provider, email: email, label: nil, status: rest.fetch(:status, "active"), status_message: nil, disabled: false,
      unavailable: rest.fetch(:unavailable, false), next_retry_after: rest[:next_retry_after], quota: rest.fetch(:quota, {}),
      quota_observed_at: rest[:quota_observed_at], created_at: created_at, updated_at: updated_at, succeeded: 0, failed: 0, sign_in_id: rest[:sign_in_id]
    )
  end

  def proxy_model(id, name: id, context_window: 272_000)
    SubscriptionProxy::Client::Model.new(id: id, name: name, context_window: context_window, max_output_tokens: 128_000, input_modalities: %w[text])
  end

  def proxy_response(code, body = {}, headers = {})
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s)
    klass.new("1.1", code.to_s, "").tap do |response|
      response.instance_variable_set(:@body, body.is_a?(String) ? body : body.to_json)
      response.instance_variable_set(:@read, true)
      headers.each { |name, value| response[name] = value }
    end
  end

  # Answers the requests in turn with these responses, and answers the requests that were sent.
  def stub_proxy(*answers)
    sent = []
    SubscriptionProxy::Client.any_instance.stubs(:transport).with do |_uri, request|
      sent << request
      true
    end.returns(*answers)
    sent
  end
end
