require "test_helper"

# A chat's reply ends with a line saying Halon's next step. One that offers a read Halon could take itself is sent back
# once to take it, and nobody ever sees the line.
class FirefightAi::NextStepTest < ActiveSupport::TestCase
  # Stands in for a RubyLLM chat that only replies in words, each reply in turn.
  class Replies
    attr_reader :messages, :model_calls

    def initialize(replies)
      @replies = replies
      @messages = []
      @model_calls = 0
    end

    def to_llm = self

    def caching = nil

    def with_tool_options(**) = self

    def awaiting_approval? = false

    def add_message(attributes) = (messages << RubyLLM::Message.new(**attributes)).last

    def step
      @model_calls += 1
      (messages << @replies.shift).last
    end
  end

  test "the line says the kind and comes off the reply, whatever its case" do
    assert_equal "read", FirefightAi::NextStep.kind("Want me to read the logs?\n[next step: read]")
    assert_equal "choice", FirefightAi::NextStep.kind("Shall I roll back?\n\n[Next step: Choice]  ")
    assert_nil FirefightAi::NextStep.kind("It was the deploy.")
    assert_equal "Want me to read the logs?", FirefightAi::NextStep.without("Want me to read the logs?\n[next step: read]")
  end

  test "as it streams the line is held back while it may still be arriving, dropped once whole, and anything else goes out" do
    shown = []
    stream = FirefightAi::NextStep::Stream.new { |text| shown << text }

    [ "It was the ", "deploy. [ne", "xt st", "ep: re", "ad]" ].each { |piece| stream.add(piece) }
    stream.finish
    assert_equal "It was the deploy.", shown.join.rstrip, "a space already sent before the line is all that shows"

    shown.clear
    other = FirefightAi::NextStep::Stream.new { |text| shown << text }
    [ "See [", "the run](https://x.test/1)." ].each { |piece| other.add(piece) }
    other.finish
    assert_equal "See [the run](https://x.test/1).", shown.join
  end

  test "a reply offering a read is sent back once to take it, and a second offer ends the turn" do
    chat = Replies.new([
      llm_reply(content: "Shall I check the logs?\n[next step: read]"),
      llm_reply(content: "Still want me to check?\n[next step: read]")
    ])
    nudges = []

    outcome = run_loop(chat, nudge: ->(text) { nudges << text })

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal [ FirefightAi::NextStep::SEND_BACK ], nudges
    assert_equal 2, chat.model_calls
  end

  test "an offer of a change, a choice or nothing ends the turn as before" do
    [ "change", "choice", "none" ].each do |kind|
      chat = Replies.new([ llm_reply(content: "Roll back?\n[next step: #{kind}]") ])
      nudges = []

      assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, run_loop(chat, nudge: ->(text) { nudges << text }).status
      assert_empty nudges, kind
    end
  end

  test "off by default, so a chat is told the line and sends a reply back only when the deployment finishes reads" do
    workspace = workspaces(:slack_workspace_one)
    assert_not FirefightAi.configuration.finish_reads
    assert_not_includes FirefightAi::Responder.new(workspace, inferable: nil).send(:template_text), FirefightAi::NextStep::RULE

    FirefightAi.configuration.stubs(:finish_reads).returns(true)
    assert_includes FirefightAi::Responder.new(workspace, inferable: nil).send(:template_text), FirefightAi::NextStep::RULE

    config = FirefightAi::Configuration.new
    config.finish_reads = "on"
    assert config.finish_reads
    assert_raises(ArgumentError) { config.finish_reads = "sometimes" }
  end

  private

  def run_loop(chat, nudge:)
    FirefightAi::AgentLoop.new(
      chat: chat, budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 400, max_turns: 10), answered: -> { false },
      reply_is_answer: true, checks: [ FirefightAi::NextStep.check ], nudge: ->(text) { nudge.call(text) || chat.add_message(role: :user, content: text) },
      inference: { workspace: workspaces(:slack_workspace_one), feature: "conversation", provider: "openai", model: "gpt-4o",
                   inferable: incidents(:active_critical_ws1) }
    ).run
  end
end
