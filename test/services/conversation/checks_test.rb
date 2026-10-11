require "test_helper"

# While Halon troubleshoots it keeps a board of two or three candidate causes. A turn that names a cause while a strong
# alternative is open goes back once, and a cause it confirms gets a second look from a separate quick call that only
# looks for evidence against it. A plain question, which never touches the board, meets neither.
class Conversation::ChecksTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @chat = @conversation.chat_record
    @turn = Conversation::Turn.new(@conversation, asker: @member)
    @tool = Chat::Tools::Theories.new(@turn)
    @since = 1.minute.ago
    @choice = FirefightAi::ModelChoice.new(model: "gpt-4o-mini")
  end

  test "the board is rewritten whole, keeps when a theory last moved, and reads back with the leading cause marked" do
    said = board!([ theory("worker's deploy raised its pool", "open", leading: true), theory("a slow query", "open") ])
    first = @chat.theories.first.status_changed_at

    travel 1.minute do
      board!([ theory("worker's deploy raised its pool", "open", leading: true), theory("a slow query", "ruled_out", evidence: "insights: p50 3 ms") ])
    end

    assert_match "1. [open] (leading) worker's deploy raised its pool", said
    assert_equal first, @chat.theories.reload.first.status_changed_at, "unchanged, it keeps when it moved"
    assert_equal %w[open ruled_out], @chat.theories.map(&:status)
    step = Chat::Tools.step(Chat::Tools::Theories::NAME, { "theories" => [ {}, {} ] })
    assert_equal [ "Theory board", "2 theories", Chat::Tools::CARD_THEORIES ], [ step.title, step.headline, step.card.kind ]
    assert_equal "insights: p50 3 ms", ChatTheorySerializer.many(@chat.theories).last[:evidence]
  end

  test "a cause named while a strong alternative is open goes back once, and a plain question never meets the board" do
    checks = Conversation::Checks.new(@chat, since: @since, choice: @choice, inferable: @conversation)
    assert_nil checks.open_board(nil), "no board, a plain question"

    board!([ theory("worker's deploy raised its pool", "confirmed", leading: true), theory("a slow query", "open") ])
    assert_match "a slow query is still open", checks.open_board(nil)

    board!([ theory("worker's deploy raised its pool", "confirmed", leading: true), theory("a slow query", "ruled_out") ])
    assert_nil checks.open_board(nil)

    board!([ theory("worker's deploy", "open"), theory("a slow query", "open") ])
    assert_match "worker's deploy and a slow query are still open", checks.open_board(nil)

    old = Conversation::Checks.new(@chat, since: 1.minute.from_now, choice: @choice, inferable: @conversation)
    assert_nil old.open_board(nil), "a board an earlier turn left is not this turn's"
  end

  test "a cause confirmed in this turn is challenged with what the turn read, and anything found sends it back with the reads to settle it" do
    read!("call_1", "search_logs", "worker boots with pool 40 since 13:38")
    board!([ theory("worker's deploy raised its pool", "confirmed", leading: true, evidence: "search_logs: pool 40") ])
    asked = nil
    FirefightAi::Challenger.any_instance.expects(:challenge).with do |cause:, reads:, facts:|
      asked = [ cause, reads, facts ]
      true
    end.returns(FirefightAi::Challenger::Verdict.new(verdict: FirefightAi::Schemas::Challenge::CONTRADICTED,
                                                      reason: "orders hit its limit at 13:36, before the deploy.", checks: [ "Read orders' connections before 13:38." ]))

    said = Conversation::Checks.new(@chat, since: @since, choice: @choice, inferable: @conversation, facts: "Suspects: worker deploy").challenge(nil)

    assert_match "worker's deploy raised its pool", asked.first
    assert_match "pool 40 since 13:38", asked.second
    assert_equal "Suspects: worker deploy", asked.third
    assert_match "orders hit its limit at 13:36", said
    assert_match "Read orders' connections before 13:38.", said
  end

  test "a cause that holds, one confirmed in an earlier turn, or a board with nothing confirmed is never challenged" do
    FirefightAi::Challenger.any_instance.stubs(:challenge).returns(FirefightAi::Challenger::Verdict.new(verdict: FirefightAi::Schemas::Challenge::HOLDS, reason: "", checks: []))
    board!([ theory("worker's deploy", "confirmed") ])
    assert_nil Conversation::Checks.new(@chat, since: @since, choice: @choice, inferable: @conversation).challenge(nil)

    FirefightAi::Challenger.any_instance.expects(:challenge).never
    board!([ theory("worker's deploy", "open") ])
    assert_nil Conversation::Checks.new(@chat, since: @since, choice: @choice, inferable: @conversation).challenge(nil)
  end

  private

  def theory(title, status, leading: false, evidence: "read it") = { "title" => title, "status" => status, "evidence" => evidence, "leading" => leading }

  def board!(theories) = @tool.call(tool_call: RubyLLM::ToolCall.new(id: "call_board_#{SecureRandom.hex(2)}", name: Chat::Tools::Theories::NAME, arguments: {}), "theories" => theories)

  def read!(tool_call_id, name, answer)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: name, arguments: {})
    call.update!(result: @chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer))
  end
end
