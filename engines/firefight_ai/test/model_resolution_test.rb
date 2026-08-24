require "test_helper"

class FirefightAi::ModelResolutionTest < ActiveSupport::TestCase
  setup do
    @original_default = FirefightAi.configuration.default_model
    @original_env = ENV["POSTMORTEM_AI_MODEL"]
  end

  teardown do
    FirefightAi.configuration.default_model = @original_default
    if @original_env.nil?
      ENV.delete("POSTMORTEM_AI_MODEL")
    else
      ENV["POSTMORTEM_AI_MODEL"] = @original_env
    end
  end

  test "the feature fallback holds when nothing is configured" do
    ENV.delete("POSTMORTEM_AI_MODEL")
    FirefightAi.configuration.default_model = nil

    assert_equal "gpt-4o", FirefightAi.model_for("POSTMORTEM_AI_MODEL", "gpt-4o")
  end

  test "the configured default model overrides the feature fallback" do
    ENV.delete("POSTMORTEM_AI_MODEL")
    FirefightAi.configuration.default_model = "claude-sonnet-5"

    assert_equal "claude-sonnet-5", FirefightAi.model_for("POSTMORTEM_AI_MODEL", "gpt-4o")
  end

  test "the feature env var wins over the configured default" do
    ENV["POSTMORTEM_AI_MODEL"] = "gpt-4o-mini"
    FirefightAi.configuration.default_model = "claude-sonnet-5"

    assert_equal "gpt-4o-mini", FirefightAi.model_for("POSTMORTEM_AI_MODEL", "gpt-4o")
  end
end
