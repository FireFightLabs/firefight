require "test_helper"

class FirefightAi::ModelResolutionTest < ActiveSupport::TestCase
  MODEL_ENV = %w[
    POSTMORTEM_AI_MODEL POSTMORTEM_AI_PROVIDER INVESTIGATION_AI_MODEL INVESTIGATION_AI_PROVIDER
    CITATION_CHECK_AI_MODEL CITATION_CHECK_AI_PROVIDER
  ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @original_default = FirefightAi.configuration.default_model
    @original_provider = FirefightAi.configuration.default_provider
    @original_quick = [ FirefightAi.configuration.quick_model, FirefightAi.configuration.quick_provider ]
    @original_env = ENV.slice(*MODEL_ENV)
    MODEL_ENV.each { |name| ENV.delete(name) }
    FirefightAi.configuration.default_model = nil
    FirefightAi.configuration.default_provider = nil
  end

  teardown do
    FirefightAi.configuration.default_model = @original_default
    FirefightAi.configuration.default_provider = @original_provider
    FirefightAi.configuration.quick_model, FirefightAi.configuration.quick_provider = @original_quick
    MODEL_ENV.each { |name| ENV.delete(name) }
    ENV.update(@original_env)
  end

  test "the table a refresh fills is the registry, so a model missing from it is unknown" do
    assert_equal RubyLLM::ActiveRecord::Model, RubyLLM.config.model_registry_store
    assert FirefightAi.registered?("gpt-4o")
    assert_not FirefightAi.registered?("gpt-5.6-sol")
  end

  test "a model is looked up as the provider that serves it, never as whichever provider the registry lists first" do
    assert FirefightAi.registered?("gpt-4o", "openai")
    assert_not FirefightAi.registered?("gpt-4o", "anthropic")
    assert FirefightAi.context_window("gpt-4o", provider: "openai")
    assert_nil FirefightAi.context_window("gpt-4o", provider: "anthropic")
    assert_equal 4096, FirefightAi.max_output_tokens("gpt-3.5-turbo", provider: "openai")
    assert_nil FirefightAi.max_output_tokens("gpt-3.5-turbo", provider: "anthropic")
  end

  test "the purpose's fallback holds when nothing is configured" do
    choice = FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)

    assert_equal "gpt-4o-mini", choice.model
    assert_nil choice.provider
    assert_equal "openai", choice.provider_name
  end

  test "a postmortem with no model of its own is written on Halon's" do
    ENV["INVESTIGATION_AI_MODEL"] = "gpt-5.6-luna"
    ENV["INVESTIGATION_AI_PROVIDER"] = "openai"

    choice = FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace)

    assert_equal "gpt-5.6-luna", choice.model
    assert_equal "openai", choice.provider
  end

  test "a workspace's Halon model carries to its postmortems, and a postmortem model still wins" do
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::INVESTIGATION, model: "claude-opus-4")

    assert_equal "claude-opus-4", FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace).model

    ENV["POSTMORTEM_AI_MODEL"] = "claude-sonnet-4"
    assert_equal "claude-sonnet-4", FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace).model
  end

  test "the deployment default overrides the fallback and carries its provider" do
    FirefightAi.configuration.default_model = "qwen3.6"
    FirefightAi.configuration.default_provider = "bedrock"

    choice = FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace)

    assert_equal "qwen3.6", choice.model
    assert_equal "bedrock", choice.provider
    assert_equal "bedrock", choice.provider_name
  end

  test "the purpose's env var wins over the deployment default" do
    ENV["POSTMORTEM_AI_MODEL"] = "claude-sonnet-4"
    FirefightAi.configuration.default_model = "gpt-4o-mini"

    assert_equal "claude-sonnet-4", FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace).model
  end

  test "a workspace override for the purpose wins over everything" do
    ENV["POSTMORTEM_AI_MODEL"] = "claude-sonnet-4"
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::ANY, model: "gpt-4o-mini")
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::POSTMORTEM, model: "llama3", provider: "ollama")

    choice = FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace)

    assert_equal "llama3", choice.model
    assert_equal "ollama", choice.provider
    assert_equal "gpt-4o-mini", FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace).model
  end

  test "another workspace's override does not leak" do
    workspaces(:slack_workspace_two).ai_model_overrides.create!(purpose: AiPurpose::ANY, model: "gpt-4o-mini")

    assert_equal "gpt-4o", FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace).model
  end

  test "a model the registry does not know is opened on its named provider" do
    choice = FirefightAi::ModelChoice.new(model: "qwen3.6", provider: "bedrock")
    RubyLLM.expects(:chat).with(model: "qwen3.6", provider: "bedrock", assume_model_exists: true).returns(:chat)

    assert_equal :chat, FirefightAi.chat(choice)
  end

  test "a registered model is opened by id alone" do
    RubyLLM.expects(:chat).with(model: "gpt-4o").returns(:chat)

    assert_equal :chat, FirefightAi.chat(FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil))
  end

  test "an override needs a known purpose and one row per purpose" do
    assert_not @workspace.ai_model_overrides.new(purpose: "telemetry", model: "gpt-4o").valid?
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::SUMMARY, model: "gpt-4o")
    assert_not @workspace.ai_model_overrides.new(purpose: AiPurpose::SUMMARY, model: "gpt-4o-mini").valid?
  end

  test "the citation check uses the investigation's model until it is given its own" do
    ENV["INVESTIGATION_AI_MODEL"] = "gpt-5.6-sol"

    assert_equal "gpt-5.6-sol", FirefightAi.model_for(AiPurpose::CITATION_CHECK, workspace: @workspace).model
  end

  test "a citation check model set for the deployment runs the check and leaves investigations alone" do
    ENV["INVESTIGATION_AI_MODEL"] = "gpt-5.6-sol"
    ENV["CITATION_CHECK_AI_MODEL"] = "z-ai/glm-4.7-flash"
    ENV["CITATION_CHECK_AI_PROVIDER"] = "openrouter"

    check = FirefightAi.model_for(AiPurpose::CITATION_CHECK, workspace: @workspace)

    assert_equal [ "z-ai/glm-4.7-flash", "openrouter" ], [ check.model, check.provider ]
    assert_equal "gpt-5.6-sol", FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace).model
  end

  test "a workspace that pins its investigation model gets it for the citation check too, unless it pins one for the check" do
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::INVESTIGATION, model: "claude-sonnet-4-5")

    assert_equal "claude-sonnet-4-5", FirefightAi.model_for(AiPurpose::CITATION_CHECK, workspace: @workspace).model

    @workspace.ai_model_overrides.create!(purpose: AiPurpose::CITATION_CHECK, model: "z-ai/glm-4.7-flash", provider: "openrouter")

    assert_equal "z-ai/glm-4.7-flash", FirefightAi.model_for(AiPurpose::CITATION_CHECK, workspace: @workspace).model
  end

  test "with a key and nothing named, Halon's loop runs on the provider's main model and side jobs on its quick one" do
    RubyLLM.config.stubs(:anthropic_api_key).returns("sk-ant-test")

    loop = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    side = FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)

    assert_equal [ "claude-sonnet-5-5", "anthropic" ], [ loop.model, loop.provider ]
    assert_equal [ "claude-haiku-4-5", "anthropic" ], [ side.model, side.provider ]
    assert_equal "claude-sonnet-5-5", FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace).model, "what grows from the loop follows it"
  end

  test "the deployment default still leads Halon's loop, and side jobs move to its provider's quick model" do
    RubyLLM.config.stubs(:anthropic_api_key).returns("sk-ant-test")
    FirefightAi.configuration.default_model = "claude-sonnet-4-5"
    FirefightAi.configuration.default_provider = "anthropic"

    assert_equal "claude-sonnet-4-5", FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace).model
    assert_equal "claude-haiku-4-5", FirefightAi.model_for(AiPurpose::MILESTONES, workspace: @workspace).model
  end

  test "FIREFIGHT_AI_QUICK_MODEL names the side jobs' model and leaves the loop alone" do
    FirefightAi.configuration.default_model = "gpt-4o"
    FirefightAi.configuration.quick_model = "gpt-3.5-turbo"

    assert_equal "gpt-3.5-turbo", FirefightAi.model_for(AiPurpose::INCIDENT_RESPONSE, workspace: @workspace).model
    assert_equal "gpt-4o", FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace).model
  end

  test "with no quick model to hand, side jobs stay on the deployment default as before" do
    FirefightAi.configuration.default_model = "qwen3.6"
    FirefightAi.configuration.default_provider = "bedrock"

    assert_equal "qwen3.6", FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace).model
  end

  test "embeddings keep their own model whatever the loop runs on" do
    RubyLLM.config.stubs(:anthropic_api_key).returns("sk-ant-test")

    assert_equal "text-embedding-3-small", FirefightAi.embedding_model
  end
end
