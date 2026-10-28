# A workspace's own AI accounts, made without the check call, and backends standing in for Firefight's cloud.
module AiAccountTestHelper
  # The cloud build's backend: Firefight's own workspaces stay on Firefight's key, the rest pay with credits. created
  # holds each workspace it was told was created, in order. house is how it describes the AI it supplies, or nil.
  HostedBackend = Struct.new(:own, :credit, :house, :created) do
    def check(_workspace, _feature) = Entitlements.allow
    def firefight_pays_for_ai?(_workspace) = own
    def ai_credit(_workspace) = credit
    def house_ai(_workspace) = house

    def workspace_created!(workspace)
      self.created ||= []
      created << workspace.id
    end
  end

  # Where the stand in for the hosted build's checkout is drawn, by tests that follow a purchase.
  CHECKOUT_PATH = "/test/credits/checkout".freeze
  PACK_CENTS = [ 2500, 5000, 10_000, 25_000 ].freeze

  # spendable: it can pay for a call now. used: it held credit and has none left. starter_micros: the starter credit
  # the workspace was given. balance: what the row says is left. included_micros: the AI the plan includes every month.
  Credit = Struct.new(:spendable, :used, :starter_micros, :balance, :included_micros) do
    def spendable? = spendable
    def used? = used
    def summary = { title: "Firefight credits", detail: "#{balance || '$12.40'} left", action: { label: "Buy credits", href: "/app/settings/billing#credits" } }
    def top_up = "An admin can buy more under Settings, Billing"

    def purchase(return_to:)
      {
        packs: PACK_CENTS.map { |cents| { cents: cents, price: "$#{cents / 100}" } },
        markupPercent: 20,
        blockedReason: nil,
        checkoutPath: "#{CHECKOUT_PATH}?#{{ return_to: return_to }.to_query}",
        starterMicros: starter_micros,
        includedMicros: included_micros
      }
    end
  end

  # Models the test registry holds, since the recommended ones are newer than its few rows.
  REGISTERED_MODELS = {
    "anthropic" => { "main" => "claude-sonnet-4-5", "fast" => "claude-haiku-4-5" },
    "openai" => { "main" => "gpt-4o", "fast" => "gpt-4o-mini" },
    "bedrock" => { "main" => "anthropic.claude-sonnet-4-5-20250929-v1:0", "fast" => "anthropic.claude-sonnet-4-5-20250929-v1:0" },
    "vertexai" => { "main" => "claude-opus-5-5", "fast" => "claude-opus-5-5" },
    "openrouter" => { "main" => "openai/shared-vision", "fast" => "openai/shared-vision" },
    "deepseek" => { "main" => "deepseek-v4-pro", "fast" => "deepseek-flash" },
    "zai" => { "main" => "glm-5.3", "fast" => "glm-5.3-flash" },
    "minimax" => { "main" => "MiniMax-M3", "fast" => "MiniMax-M3.1-Flash" },
    "qwen" => { "main" => "qwen3.8-max", "fast" => "qwen3.8-flash" }
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

  def on_firefights_cloud!(own: false, credit: nil, house: nil)
    Entitlements.backend = HostedBackend.new(own, credit, house)
  end
end
