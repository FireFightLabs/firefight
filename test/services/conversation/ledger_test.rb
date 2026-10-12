require "test_helper"

# Every model call made for a chat is ledgered under that chat, whatever it is about, so a chat's cost can be summed from
# the ledger alone. A watch's calls are ledgered under the watch, which belongs to the chat that started it.
class Conversation::LedgerTest < ActiveSupport::TestCase
  ANSWERED = FirefightAi::AgentLoop::STATUS_ANSWERED

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @conversation = @workspace.conversations.create!(
      subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id,
      thread_id: "1700000000.000100", started_by: @alice, max_turns: 40, max_spend_cents: 50
    )
    stub_post_message
    stub_agent_session
    # Every reply below is scripted, so the key is never sent anywhere.
    RubyLLM.config.stubs(:openai_api_key).returns("sk-test")
    Conversation::Checks.any_instance.stubs(:all).returns([])
  end

  test "a chat turn about an incident is ledgered under the chat, not the incident" do
    RubyLLM::Provider.any_instance.stubs(:complete).returns(llm_reply(content: "Checkout is healthy.", cost: 0.01))

    @conversation.ask!("how is checkout")
    Conversation::Runner.new(@conversation, asker: @alice).run

    turn = Inference.where(workspace: @workspace, feature: FirefightAi::Responder::FEATURE).sole
    assert_equal [ @conversation, @alice ], [ turn.inferable, turn.member ]
    assert_equal 10_000, Inference.where(inferable: @conversation).sum(:cost_micros)
  end

  test "a turn hands the chat to the challenger and to the helpers it starts, so their calls are ledgered under it too" do
    responder = stub(ai_model: FirefightAi::ModelChoice.new(model: "gpt-4o"))
    responder.stubs(:run).with { |tools:, **| @share = tools.find { |tool| tool.name == Chat::Tools::Helpers::NAME }.instance_variable_get(:@share) }
             .returns(FirefightAi::AgentLoop::Outcome.new(status: ANSWERED, turns_used: 1, spent_micros: 0))
    FirefightAi::Responder.expects(:new).with { |_workspace, inferable:, **| inferable == @conversation }.returns(responder)
    Conversation::Checks.expects(:new).with { |_chat, inferable:, member:, **| [ inferable, member ] == [ @conversation, @alice ] }.returns(stub(all: []))

    @conversation.ask!("how is checkout")
    Conversation::Runner.new(@conversation, asker: @alice).run

    assert_equal [ @conversation, @alice ], [ @share.inferable, @share.member ]
  end

  test "a helper's calls are ledgered under the chat it checks for" do
    RubyLLM::Provider.any_instance.stubs(:complete).returns(llm_reply(content: "Nothing new in the logs.", cost: 0.002))

    hand_off(Chat::Helpers::Check.new(title: "Logs of web", brief: "Read the logs of web", deep: false))

    helper = Inference.where(workspace: @workspace, feature: FirefightAi::Helper::FEATURE).sole
    assert_equal [ @conversation, @alice ], [ helper.inferable, helper.member ]
  end

  test "a specialist's calls are ledgered under the chat it reads for" do
    RubyLLM::Provider.any_instance.stubs(:complete).returns(llm_reply(content: "Nothing in the tickets.", cost: 0.002))
    turn = Conversation::Turn.new(@conversation, asker: @alice)
    turn.asks_specialists = true

    hand_off(Chat::Helpers::Check.new(title: "Tickets", brief: "Read open tickets", deep: false, domain: Chat::Specialists::TICKETS),
             specialists: Chat::Specialists::Live.new(turn))

    specialist = Inference.where(workspace: @workspace, feature: FirefightAi::Specialist::FEATURE).sole
    assert_equal [ @conversation, @alice ], [ specialist.inferable, specialist.member ]
  end

  test "a watch's calls are ledgered under the watch, which names the chat that started it" do
    Investigation.stubs(:unavailable_reason).returns(nil)
    RubyLLM::Provider.any_instance.stubs(:complete).returns(llm_reply(content: "The tests failed.", cost: 0.001))
    watch = Chat::Watch.create!(chat: @conversation.chat_record, workspace: @workspace, asker: @alice, title: "the release",
                                purpose: "ship main", expires_at: 1.hour.from_now, limit_basis: Chat::Watch::BASIS_DEFAULT)

    assert_equal "The tests failed.", Conversation::Watches.judge(watch).why_failed(what: "Release run", evidence: "FAILED")

    judged = Inference.where(workspace: @workspace, feature: FirefightAi::WatchJudge::FEATURE).sole
    assert_equal [ watch, @alice ], [ judged.inferable, judged.member ]
    assert_equal @conversation, judged.inferable.chat.owner
  end

  private

  def hand_off(check, specialists: nil)
    @conversation.ask!("how is checkout")
    conversation = @conversation
    alice = @alice
    share = Chat::Helpers::Share.new(
      purse: FirefightAi::AgentLoop::Purse.new, max_spend_cents: 400, since: 1.minute.ago, canceled: -> { false }, moved: ->(_key) { },
      fresh_parent: -> { Conversation::Turn.new(Conversation.find(conversation.id), asker: alice, reads_only: true) },
      choose: ->(_deep) { FirefightAi::ModelChoice.new(model: "gpt-4o-mini") }, inferable: conversation, member: alice, specialists: specialists
    )
    result = Chat::Helpers.run!(Conversation::Turn.new(conversation, asker: alice), share: share, tool_call_id: "call_1", checks: [ check ])
    assert_not result.failed, result.text
  end
end
