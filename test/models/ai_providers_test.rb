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

      [ provider.main_models.last, provider.fast_model, provider.backup_models.last ].compact.each do |model_id|
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
    assert_equal [ "claude-haiku-4-5", "anthropic" ], AiProviders.deployment_choice(WorkspaceAiAccount::FAST, config: keyed).to_h.values_at(:model, :provider)
    assert_equal [ "z-ai/glm-5.2", "openrouter" ],
                 AiProviders.deployment_choice(WorkspaceAiAccount::FAST, prefer: "openrouter", config: keyed).to_h.values_at(:model, :provider)
  end

  test "the deployment's backups try other providers first, then the failing provider's own backup, never the model that failed" do
    keyed = RubyLLM.config.dup
    keyed.anthropic_api_key = "sk-ant-deployment"
    keyed.openrouter_api_key = "sk-or-deployment"
    backups = ->(model, provider) { AiProviders.deployment_backup_choices(FirefightAi::ModelChoice.new(model: model, provider: provider), config: keyed).map { |choice| choice.to_h.values_at(:model, :provider) } }

    assert_equal [ [ "z-ai/glm-5.2", "openrouter" ] ], backups.call("claude-sonnet-5-5", "anthropic"), "Anthropic has no backup of its own, so only its main model, which failed"
    assert_equal [ [ "claude-sonnet-5-5", "anthropic" ], [ "z-ai/glm-5.2", "openrouter" ] ], backups.call("anthropic/claude-sonnet-5.5", "openrouter")
    assert_equal [ [ "claude-sonnet-5-5", "anthropic" ] ], backups.call("z-ai/glm-5.2", "openrouter")
  end
end
