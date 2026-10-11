require "test_helper"

class Chat::ModelSwitchTest < ActiveSupport::TestCase
  Response = Struct.new(:status, :body, :headers)

  setup do
    @workspace = workspaces(:slack_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = @workspace.chats.create!(owner: conversation, model: "claude-opus-5-5", provider: :anthropic)
    @opus = FirefightAi::ModelChoice.new(model: "claude-opus-5-5", provider: "anthropic")
    @haiku = FirefightAi::ModelChoice.new(model: "claude-haiku-5-5", provider: "anthropic")
  end

  test "a switch says in one plain line why, by the names people know the models by" do
    said = {
      RubyLLM::OverloadedError.new("Overloaded", response: Response.new(529, {}, {})) =>
        "Claude Opus 5.5 is not answering, so I switched to Claude Haiku 5.5 for this reply.",
      RubyLLM::Error.new("Publisher model not found", response: Response.new(404, {}, {})) =>
        "Claude Opus 5.5 is not available on this account, so I switched to Claude Haiku 5.5 for this reply.",
      RubyLLM::PaymentRequiredError.new("Insufficient credits", response: Response.new(402, {}, {})) =>
        "The account behind Claude Opus 5.5 is out of credit, so I switched to Claude Haiku 5.5 for this reply.",
      RubyLLM::UnauthorizedError.new("invalid x-api-key", response: Response.new(401, {}, {})) =>
        "The key behind Claude Opus 5.5 was refused, so I switched to Claude Haiku 5.5 for this reply."
    }

    said.each do |error, line|
      assert_equal line, Chat::ModelSwitch.record!(@chat, failed: @opus, backup: @haiku, error: error).shown_as
    end
  end

  test "a run says the switch holds for the rest of the run, and a model nobody named keeps its id" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)
    chat = @workspace.chats.create!(owner: investigation, model: "claude-opus-5-5", provider: :anthropic)

    switch = Chat::ModelSwitch.record!(chat, failed: @opus, backup: FirefightAi::ModelChoice.new(model: "some-new-model", provider: "openai"),
                                             error: Faraday::TimeoutError.new("timed out"))

    assert_equal "Claude Opus 5.5 is not answering, so I switched to some-new-model for the rest of this run.", switch.shown_as
  end
end
