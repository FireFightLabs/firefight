require "test_helper"

class FirefightAi::ModelResolutionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @original_default = FirefightAi.configuration.default_model
    @original_provider = FirefightAi.configuration.default_provider
    @original_env = ENV.slice("POSTMORTEM_AI_MODEL", "POSTMORTEM_AI_PROVIDER")
    ENV.delete("POSTMORTEM_AI_MODEL")
    ENV.delete("POSTMORTEM_AI_PROVIDER")
    FirefightAi.configuration.default_model = nil
    FirefightAi.configuration.default_provider = nil
  end

  teardown do
    FirefightAi.configuration.default_model = @original_default
    FirefightAi.configuration.default_provider = @original_provider
    ENV.delete("POSTMORTEM_AI_MODEL")
    ENV.delete("POSTMORTEM_AI_PROVIDER")
    ENV.update(@original_env)
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
end
