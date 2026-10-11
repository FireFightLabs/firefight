require "test_helper"

class AiProvidersTest < ActiveSupport::TestCase
  # Read from the catalog RubyLLM ships, which the nightly refresh fills the registry from. The test registry holds a
  # few rows only. A newer main model ahead of it is picked up once the registry holds it, and the last is always there.
  test "every recommended model is one the catalog holds for its provider, with tool calling and a known size" do
    catalog = JSON.parse(File.read(File.join(Gem.loaded_specs["ruby_llm"].full_gem_path, "lib/ruby_llm/models.json")))
                  .index_by { |model| [ model["provider"], model["id"] ] }
    AiProviders.all.each do |provider|
      # A deployment's own models, such as an Azure deployment or a local Ollama, are named by whoever runs them.
      next if provider.assumes_models || provider.local

      [ provider.main_models.last, *provider.fast_models.map { |entry| Array(entry).last }, *provider.backup_models.map { |entry| Array(entry).last } ].compact.each do |model_id|
        model = catalog[[ provider.slug, model_id ]]
        assert model, "#{provider.slug} offers #{model_id}"
        assert_includes model["capabilities"], "function_calling", "#{provider.slug} #{model_id} calls tools"
        assert model["context_window"].to_i.positive?, "Halon can size #{provider.slug} #{model_id}"
      end
    end
  end

  test "what a provider asks for comes from RubyLLM, with Bedrock and Vertex AI made to bring their own keys" do
    bedrock = AiProviders.find("bedrock")
    assert_equal %w[api_key region secret_key], bedrock.fields.select(&:required).map(&:key).sort
    assert_not bedrock.field("credential_provider"), "an object a server holds is never asked for"
    assert AiProviders.find("vertexai").field("service_account_key").required
    assert(AiProviders.find("openai").fields.all? { |field| RubyLLM::Configuration.options.include?(field.option) })
  end

  test "the models a chat can switch to are listed only for providers offered, each named and described as plain copy" do
    listed = YAML.load_file(AiProviders::REGISTRY_PATH).fetch("chat_models")

    assert_empty listed.keys - AiProviders.all.map(&:slug)
    assert_not_includes AiProviders.all.map(&:slug), "chat_models"
    listed.each do |slug, entries|
      assert_not AiProviders.find(slug).assumes_models, "#{slug} names its models itself"
      assert_equal entries.size, entries.pluck("model").uniq.size
      entries.each do |entry|
        assert_equal %w[label model note], entry.keys.sort
        assert_no_match(/[—;]/, "#{entry["label"]} #{entry["note"]}")
      end
    end
  end

  test "a listed model the registry cannot bill or size is left out" do
    assert_equal [ "anthropic/claude-haiku-5.5", "z-ai/glm-5.2", "anthropic/claude-sonnet-5.5", "anthropic/claude-opus-5.5" ], AiProviders.chat_models("openrouter").map(&:model)

    FirefightAi.stubs(:priced_for?).returns(false)
    assert_empty AiProviders.chat_models("openrouter")
    assert_empty AiProviders.chat_models("ollama")
  end

  test "code fixes are offered where the model proxy reaches" do
    assert_equal %w[anthropic openai openrouter], AiProviders.all.select(&:code_fixes).map(&:slug).sort
  end

  test "an env var replaces a provider's code fix model, and the registry's pick stands without one" do
    entry = YAML.load_file(AiProviders::REGISTRY_PATH).fetch("anthropic")
    assert_equal "claude-opus-5-5", AiProviders.send(:build, "anthropic", entry).code_fix_model

    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("ANTHROPIC_CODE_FIX_MODEL").returns("claude-sonnet-5-5")
    assert_equal "claude-sonnet-5-5", AiProviders.send(:build, "anthropic", entry).code_fix_model
  end

  test "Sign in with ChatGPT is offered only behind its flag, and only once every address it needs is set" do
    workspace = workspaces(:slack_workspace_one)
    env = { "CHATGPT_OAUTH_CLIENT_ID" => "client", "CHATGPT_OAUTH_AUTHORIZE_URL" => "https://auth.example.com/authorize",
            "CHATGPT_OAUTH_TOKEN_URL" => "https://auth.example.com/token", "CHATGPT_API_BASE" => "https://api.example.com/v1" }
    ENV.stubs(:[]).returns(nil)
    env.each { |name, value| ENV.stubs(:[]).with(name).returns(value) }

    assert_nil AiProviders.sign_in_for(workspace)
    FeatureFlags.enable!(workspace, FeatureFlags::CHATGPT_SIGN_IN)
    assert_equal "openai", AiProviders.sign_in_for(workspace).slug

    ENV.stubs(:[]).with("CHATGPT_OAUTH_TOKEN_URL").returns(nil)
    assert_nil AiProviders.sign_in_for(workspace)
  end

  test "the main model is the first the registry can price and size, and the one the catalog ships otherwise" do
    anthropic = AiProviders.find("anthropic")
    assert_equal "claude-sonnet-5-5", anthropic.main_model

    FirefightAi.stubs(:priced_for?).returns(false)
    assert_equal anthropic.main_models.last, anthropic.main_model
  end

  test "the deployment's pick for a role needs a key and prefers the provider asked for" do
    keyed = RubyLLM.config.dup
    keyed.anthropic_api_key = "sk-ant-deployment"
    keyed.openrouter_api_key = "sk-or-deployment"

    assert_nil AiProviders.deployment_choice(WorkspaceAiAccount::MAIN), "no key, no pick"
    assert_equal [ "claude-sonnet-5-5", "anthropic" ], AiProviders.deployment_choice(WorkspaceAiAccount::MAIN, config: keyed).to_h.values_at(:model, :provider)
    assert_equal "openrouter", AiProviders.deployment_choice(WorkspaceAiAccount::MAIN, prefer: "openrouter", config: keyed).provider
    assert_equal [ "claude-haiku-5-5", "anthropic" ], AiProviders.deployment_choice(WorkspaceAiAccount::FAST, config: keyed).to_h.values_at(:model, :provider)
    assert_equal [ "anthropic/claude-haiku-5.5", "openrouter" ],
                 AiProviders.deployment_choice(WorkspaceAiAccount::FAST, prefer: "openrouter", config: keyed).to_h.values_at(:model, :provider)
  end

  test "quick work and the backup run on Claude Haiku 5.5 where the provider runs it, Mistral on GLM-5.2, and the catalog's Haiku until the registry prices 5.5" do
    assert_equal [ "claude-haiku-5-5", "anthropic/claude-haiku-5.5" ], %w[anthropic openrouter].map { |slug| AiProviders.find(slug).fast_model }
    assert_equal [ "claude-haiku-5-5" ], AiProviders.find("anthropic").backup_models_ready
    assert_equal "glm-5-2", AiProviders.find("mistral").fast_model
    assert_equal "claude-sonnet-5-5", AiProviders.find("vertexai").main_models.first

    FirefightAi.stubs(:priced_for?).returns(false)
    assert_equal "claude-haiku-4-5", AiProviders.find("anthropic").fast_model
  end

  test "Vertex AI tries Claude Haiku and then Gemini, so a project without Claude enabled still answers" do
    FirefightAi.stubs(:priced_for?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)

    assert_equal [ "claude-haiku-5-5", "gemini-3.1-pro-preview" ], AiProviders.find("vertexai").backup_models_ready
  end

  test "quick work on Vertex AI carries on from Claude Haiku to Gemini's fast model, on the same account, and never past the list" do
    FirefightAi.stubs(:priced_for?).returns(true)
    haiku = FirefightAi::ModelChoice.new(model: "claude-haiku-5-5", provider: "vertexai", payer: AiPayer.house(Inference::PAID_BY_OPERATOR))

    gemini = AiProviders.quick_fallback(haiku)

    assert_equal [ "gemini-3.8-flash", "vertexai", haiku.payer ], [ gemini.model, gemini.provider, gemini.payer ]
    assert_nil AiProviders.quick_fallback(gemini), "nothing after Gemini"
    assert_nil AiProviders.quick_fallback(haiku.with(model: "a-model-an-admin-picked")), "an admin's own pick is theirs to change"
    assert_nil AiProviders.quick_fallback(FirefightAi::ModelChoice.new(model: "claude-haiku-5-5", provider: "anthropic")), "Anthropic has no other quick model"
  end

  test "a workspace's own account carries on with its provider's backups, on the same account, never the model that failed" do
    account = add_ai_account!(workspaces(:slack_workspace_one), key: "sk-ant-own")
    failing = account.choice_for(AiPurpose::INVESTIGATION)

    backups = AiProviders.account_backup_choices(failing)

    assert_equal [ [ "claude-haiku-5-5", account ] ], backups.map { |choice| [ choice.model, choice.payer.account ] }
    assert_equal failing.context, backups.sole.context, "the customer's own key"
    assert_empty AiProviders.account_backup_choices(backups.sole)
  end

  test "the deployment's backups try other providers first, then the failing provider's own backup, never the model that failed" do
    keyed = RubyLLM.config.dup
    keyed.anthropic_api_key = "sk-ant-deployment"
    keyed.openrouter_api_key = "sk-or-deployment"
    backups = ->(model, provider) { AiProviders.deployment_backup_choices(FirefightAi::ModelChoice.new(model: model, provider: provider), config: keyed).map { |choice| choice.to_h.values_at(:model, :provider) } }

    assert_equal [ [ "anthropic/claude-haiku-5.5", "openrouter" ], [ "claude-haiku-5-5", "anthropic" ] ], backups.call("claude-sonnet-5-5", "anthropic")
    assert_equal [ [ "claude-haiku-5-5", "anthropic" ], [ "anthropic/claude-haiku-5.5", "openrouter" ] ], backups.call("anthropic/claude-sonnet-5.5", "openrouter")
    assert_equal [ [ "claude-haiku-5-5", "anthropic" ] ], backups.call("anthropic/claude-haiku-5.5", "openrouter"), "never the model that failed"
  end
end
