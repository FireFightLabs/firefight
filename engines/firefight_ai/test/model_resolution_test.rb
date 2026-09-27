require "test_helper"

class FirefightAi::ModelResolutionTest < ActiveSupport::TestCase
  MODEL_ENV = %w[
    POSTMORTEM_AI_MODEL POSTMORTEM_AI_PROVIDER INVESTIGATION_AI_MODEL INVESTIGATION_AI_PROVIDER
    CONVERSATION_AI_MODEL CONVERSATION_AI_PROVIDER CITATION_CHECK_AI_MODEL CITATION_CHECK_AI_PROVIDER
  ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @original_default = FirefightAi.configuration.default_model
    @original_provider = FirefightAi.configuration.default_provider
    @original_env = ENV.slice(*MODEL_ENV)
    MODEL_ENV.each { |name| ENV.delete(name) }
    FirefightAi.configuration.default_model = nil
    FirefightAi.configuration.default_provider = nil
  end

  teardown do
    FirefightAi.configuration.default_model = @original_default
    FirefightAi.configuration.default_provider = @original_provider
    MODEL_ENV.each { |name| ENV.delete(name) }
    ENV.update(@original_env)
  end

  test "the table a refresh fills is the registry, so a model missing from it is unknown" do
    assert_equal RubyLLM::ActiveRecord::Model, RubyLLM.config.model_registry_store
    assert FirefightAi.registered?("gpt-4o")
    assert_not FirefightAi.registered?("gpt-5.6-sol")
  end

  test "the purpose's fallback holds when nothing is configured" do
    choice = FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace)

    assert_equal "gpt-4o", choice.model
    assert_nil choice.provider
    assert_equal "openai", choice.provider_name
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

  test "the chat and the citation check use the investigation's model until they are given their own" do
    ENV["INVESTIGATION_AI_MODEL"] = "gpt-5.6-sol"

    assert_equal "gpt-5.6-sol", FirefightAi.model_for(AiPurpose::CONVERSATION, workspace: @workspace).model
    assert_equal "gpt-5.6-sol", FirefightAi.model_for(AiPurpose::CITATION_CHECK, workspace: @workspace).model
  end

  test "a chat model set for the deployment answers chats and leaves investigations alone" do
    ENV["INVESTIGATION_AI_MODEL"] = "gpt-5.6-sol"
    ENV["CONVERSATION_AI_MODEL"] = "z-ai/glm-5.3"
    ENV["CONVERSATION_AI_PROVIDER"] = "openrouter"

    chat = FirefightAi.model_for(AiPurpose::CONVERSATION, workspace: @workspace)

    assert_equal [ "z-ai/glm-5.3", "openrouter" ], [ chat.model, chat.provider ]
    assert_equal "gpt-5.6-sol", FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace).model
  end

  test "a workspace that pins its investigation model gets it for chats too, unless it pins a chat model" do
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::INVESTIGATION, model: "claude-sonnet-4-5")

    assert_equal "claude-sonnet-4-5", FirefightAi.model_for(AiPurpose::CONVERSATION, workspace: @workspace).model

    @workspace.ai_model_overrides.create!(purpose: AiPurpose::CONVERSATION, model: "z-ai/glm-5.3-flash", provider: "openrouter")

    assert_equal "z-ai/glm-5.3-flash", FirefightAi.model_for(AiPurpose::CONVERSATION, workspace: @workspace).model
  end
end
