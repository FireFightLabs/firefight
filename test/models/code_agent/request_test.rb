require "test_helper"

class CodeAgent::RequestTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = @workspace.conversations.create!(kind: Conversation::KIND_PERSONAL, started_by: @bob, max_turns: 10, max_spend_cents: 50)
    @chat = @conversation.chat_record
  end

  test "a change asked for in a chat carries the person's own words, verbatim, and the reads before it, never Halon's words or a credential" do
    @chat.messages.create!(role: Chat::Message::ROLE_USER, content: "Make the release job send the commit")
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "I will change release.yml.")
    read = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    read.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Mcp::Tools::GET_RESOURCE_MAP, arguments: {})
    @chat.add_message(role: :tool, content: FirefightAi::Evidence.frame("get_resource_map", "release runs on tag push, token ghp_#{'a' * 36}"), tool_call_id: "call_1")
    @chat.messages.create!(role: Chat::Message::ROLE_USER, content: "No, the tag, not the commit")
    asking = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    asking.ruby_llm_tool_calls.create!(tool_call_id: "call_2", name: "github_fix_code", arguments: { "repo" => "acme/api" })

    request = Conversation::Turn.new(@conversation, asker: @bob).code_agent_request("call_2", evidence: CodeAgent::ChatEvidence.for(@chat, @workspace, before: "call_2"))

    assert_equal [ "Make the release job send the commit", "No, the tag, not the commit" ], request.words
    assert_equal [ "release runs on tag push, token [REDACTED:github_token]" ], request.evidence.map(&:text)
    assert_equal [ @bob, @conversation, "call_2", @conversation.code_box_key ], [ request.principal, request.place, request.tool_call_id, request.box_key ]
  end

  test "the newest words and results are kept when there is more than fits" do
    words = Array.new(10) { |index| "message #{index} #{'x' * 1_000}" }
    evidence = Array.new(12) { |index| CodeAgent::Request::Evidence.new(label: "read #{index}", text: "y" * 3_000) }

    request = CodeAgent::Request.new(principal: @bob, source: AbilityGateway::SOURCE_CONVERSATION, words: words, evidence: evidence)

    assert request.words.last.start_with?("message 9")
    assert_operator request.words.sum(&:length), :<=, CodeAgent::Request::WORDS_LIMIT
    assert_equal "read 11", request.evidence.last.label
    assert_operator request.evidence.size, :<=, CodeAgent::Request::EVIDENCE_ITEMS
    assert(request.evidence.all? { |item| item.text.length <= CodeAgent::Request::EVIDENCE_ITEM_LIMIT })
  end

  test "the agent handed the person's words is told to quote them exactly when it gives them as a reason" do
    request = CodeAgent::Request.new(principal: @bob, source: AbilityGateway::SOURCE_CONVERSATION, words: [ "Never silently create another workspace" ])

    assert_includes request.asked_section, FirefightAi::Copy::QUOTING
    assert_includes request.asked_section, "> Never silently create another workspace"
  end
end
