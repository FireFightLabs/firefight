require "test_helper"

class Chat::Tools::HelpersTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    @chat = @conversation.chat_record
    @turn = Conversation::Turn.new(@conversation, asker: @bob)
    @share = Chat::Helpers::Share.new(
      purse: FirefightAi::AgentLoop::Purse.new, max_spend_cents: 400, since: 1.minute.ago, canceled: -> { false }, moved: -> { },
      fresh_parent: -> { @turn }, choose: ->(_deep) { FirefightAi::ModelChoice.new(model: "gpt-4o") },
      inferable: @conversation, member: @bob
    )
    @tool = Chat::Tools::Helpers.new(@turn, share: @share)
  end

  test "the checks are handed off with their titles and briefs, and what came back reaches the model framed as evidence" do
    Chat::Helpers.expects(:run!).with do |agent_run, share:, tool_call_id:, checks:|
      agent_run == @turn && share == @share && tool_call_id == "call_1" &&
        checks == [ Chat::Helpers::Check.new(title: "Logs of web", brief: "Read web's error logs", deep: false),
                    Chat::Helpers::Check.new(title: "Code", brief: "Read the handler", deep: true) ]
    end.returns(Chat::Helpers::Result.new(text: "Helpers reported, 2 of 2:", failed: false))

    said = @tool.call(tool_call: tool_call("call_1"), checks: [
      { "title" => "Logs of web", "brief" => "Read web's error logs" }, { "title" => "Code", "brief" => "Read the handler", "deep" => true }
    ])

    assert_match(/\A<#{FirefightAi::Evidence::TAG} /, said)
    assert_includes said, "Helpers reported, 2 of 2:"
  end

  test "a call where no helper reported is marked failed, so the step shows it" do
    asked = @chat.add_message(role: Chat::Message::ROLE_ASSISTANT, content: "")
    asked.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Chat::Tools::Helpers::NAME, arguments: {})
    Chat::Helpers.stubs(:run!).returns(Chat::Helpers::Result.new(text: Chat::Helpers::NO_BUDGET, failed: true))

    @tool.call(tool_call: tool_call("call_1"), checks: [ { "title" => "Logs", "brief" => "Read the logs" } ])

    assert_equal [ "call_1" ], @chat.failed_tool_call_ids
  end

  test "a check with no brief is not handed off" do
    Chat::Helpers.expects(:run!).never

    assert_equal "Give at least one check with a title and a brief.", @tool.call(tool_call: tool_call("call_1"), checks: [ { "title" => "Logs" } ])
  end

  test "a person reads the step as the checks it handed off, and the step draws the helpers while they work" do
    step = Chat::Tools.step(Chat::Tools::Helpers::NAME, { "checks" => [ { "title" => "Logs of web", "brief" => "Read web's error logs" },
                                                                        { "title" => "Recent deploys", "brief" => "List deploys since 14:00" } ] })

    assert_equal [ "2 checks at once", "Logs of web, Recent deploys" ], [ step.title, step.headline ]
    assert_equal [ [ "Logs of web", "Read web's error logs" ], [ "Recent deploys", "List deploys since 14:00" ] ], step.asked
    assert_equal Chat::Tools::CARD_HELPERS, step.card.kind
    assert step.card.shown_while_running?
    assert_equal Chat::Tools::KIND_READ, Chat::Tools.kind(Chat::Tools::Helpers::NAME, @workspace)
  end

  test "it is offered in a chat and a run only where the runner lends its helpers something" do
    assert_not_includes Conversation::Tools.for(@turn, offer: ->(_tools) { }).map(&:name), Chat::Tools::Helpers::NAME
    assert_includes Conversation::Tools.for(@turn, offer: ->(_tools) { }, helpers: @share).map(&:name), Chat::Tools::Helpers::NAME
  end

  private

  def tool_call(id) = RubyLLM::ToolCall.new(id: id, name: Chat::Tools::Helpers::NAME, arguments: {})
end
