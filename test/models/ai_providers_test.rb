require "test_helper"

class AiProvidersTest < ActiveSupport::TestCase
  # Read from the catalog RubyLLM ships, which the nightly refresh fills the registry from. The test registry holds a
  # few rows only.
  test "every recommended model is one the catalog holds for its provider, with tool calling and a known size" do
    catalog = JSON.parse(File.read(File.join(Gem.loaded_specs["ruby_llm"].full_gem_path, "lib/ruby_llm/models.json")))
                  .index_by { |model| [ model["provider"], model["id"] ] }
    AiProviders.all.each do |provider|
      # A deployment's own models, such as an Azure deployment or a local Ollama, are named by whoever runs them.
      next if provider.assumes_models || provider.local

      [ provider.main_model, provider.fast_model ].each do |model_id|
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
end
