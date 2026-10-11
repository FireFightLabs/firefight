require "test_helper"

# Halon's own loop runs at the lowest temperature, so two runs of one question differ as little as the model allows,
# and a model the registry says takes no temperature is never sent one.
class FirefightAi::LoopTemperatureTest < ActiveSupport::TestCase
  test "each provider's own by default, a number from 0 to 2 when set, and anything else is refused at boot" do
    config = FirefightAi::Configuration.new

    assert_nil config.loop_temperature
    config.loop_temperature = "0"
    assert_in_delta 0.0, config.loop_temperature
    config.loop_temperature = "0.3"
    assert_in_delta 0.3, config.loop_temperature
    config.loop_temperature = "none"
    assert_nil config.loop_temperature
    assert_raises(ArgumentError) { config.loop_temperature = "warm" }
    assert_raises(ArgumentError) { config.loop_temperature = "3" }
  end

  test "a model that takes no temperature is sent none, and any other the configured one" do
    FirefightAi.configuration.stubs(:loop_temperature).returns(0.0)
    takes = stub(metadata: { temperature: true })
    refuses = stub(metadata: { temperature: false })
    RubyLLM.models.stubs(:find).with("gpt-4o", provider: "openai").returns(takes)
    RubyLLM.models.stubs(:find).with("o3", provider: "openai").returns(refuses)

    assert_in_delta 0.0, FirefightAi.loop_temperature(FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"))
    assert_nil FirefightAi.loop_temperature(FirefightAi::ModelChoice.new(model: "o3", provider: "openai"))

    FirefightAi.configuration.unstub(:loop_temperature)
    assert_nil FirefightAi.loop_temperature(FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"))
  end

  test "the loop sets it on the chat, and again for a model that takes over, while a helper's loop leaves it alone" do
    FirefightAi.configuration.stubs(:loop_temperature).returns(0.0)
    llm = mock("llm")
    llm.stubs(:messages).returns([])
    llm.expects(:with_temperature).with(0.0).once
    chat = stub(to_llm: llm)

    loop_for(chat, steady: true)
    loop_for(stub(to_llm: stub(messages: [])), steady: false)
  end

  private

  def loop_for(chat, steady:)
    FirefightAi::AgentLoop.new(
      chat: chat, budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 400, max_turns: 10), answered: -> { false },
      inference: { workspace: workspaces(:slack_workspace_one), feature: "conversation", provider: "openai", model: "gpt-4o",
                   inferable: incidents(:active_critical_ws1) }, steady: steady
    )
  end
end
