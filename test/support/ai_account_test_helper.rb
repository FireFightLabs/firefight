# A workspace's own AI accounts, made without the check call, and backends standing in for Firefight's cloud.
module AiAccountTestHelper
  # The cloud build's backend: Firefight's own workspaces stay on Firefight's key, the rest pay with credits.
  HostedBackend = Struct.new(:own, :credit) do
    def check(_workspace, _feature) = Entitlements.allow
    def firefight_pays_for_ai?(_workspace) = own
    def ai_credit(_workspace) = credit
  end

  # spendable: it can pay for a call now. used: it held credit and has none left.
  Credit = Struct.new(:spendable, :used) do
    def spendable? = spendable
    def used? = used
    def summary = { title: "Firefight credits", detail: "$12.40 left", action: { label: "Buy credits", href: "/app/settings/billing#credits" } }
    def top_up = "An admin can buy more under Settings, Billing"
  end

  # Models the test registry holds, since the recommended ones are newer than its few rows.
  REGISTERED_MODELS = {
    "anthropic" => { "main" => "claude-sonnet-4-5", "fast" => "claude-haiku-4-5" },
    "openai" => { "main" => "gpt-4o", "fast" => "gpt-4o-mini" },
    "bedrock" => { "main" => "anthropic.claude-sonnet-4-5-20250929-v1:0", "fast" => "anthropic.claude-sonnet-4-5-20250929-v1:0" },
    "vertexai" => { "main" => "claude-opus-5-5", "fast" => "claude-opus-5-5" },
    "openrouter" => { "main" => "openai/shared-vision", "fast" => "openai/shared-vision" }
  }.freeze

  def add_ai_account!(workspace, provider: "anthropic", key: "sk-ant-own-key-4f2a", label: nil, settings: {}, models: nil, **attributes)
    models ||= REGISTERED_MODELS.fetch(provider, REGISTERED_MODELS["openai"])
    account = workspace.workspace_ai_accounts.new(provider: provider, label: label || "#{provider} account", kind: AiProviders::KIND_API_KEY,
                                                  **attributes)
    account.assign_settings({ "api_key" => key }.compact.merge(settings))
    account.assign_models(models)
    account.save_in_position!
    account
  end

  def on_firefights_cloud!(own: false, credit: nil)
    Entitlements.backend = HostedBackend.new(own, credit)
  end
end
