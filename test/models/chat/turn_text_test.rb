require "test_helper"

class Chat::TurnTextTest < ActiveSupport::TestCase
  setup do
    workspace = workspaces(:slack_workspace_one)
    conversation = Conversation.start_personal!(workspace: workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    @chat.add_message(role: :user, content: "Fix the review comments on PR 14")
    @calls = 0
  end

  test "words written before a call in the same turn are a status line, and the turn's last words are its result" do
    plan = said("Plan: fix 8 review comments on PR 14, then reply to each.", calls: 1)
    quiet = said("", calls: 2)
    update = said("I'm going to update the PR now.", calls: 1)
    done = said("Fixed all 8 and replied to each.")

    assert_equal({ plan.id => Chat::TurnText::STATUS, update.id => Chat::TurnText::STATUS, done.id => Chat::TurnText::RESULT },
                 Chat::TurnText.roles([ plan, quiet, update, done ]))
  end

  test "words a reply was sent back from count as a status line once a later call in the turn exists" do
    offered = said("Want me to read the logs?")
    assert_equal Chat::TurnText::RESULT, Chat::TurnText.roles([ offered ])[offered.id]

    said("", calls: 1)
    said("The logs show a timeout.")

    assert_equal Chat::TurnText::STATUS, Chat::TurnText.roles([ offered ])[offered.id]
  end

  test "words that put a change to the person stay a question, even once it was approved and the turn carried on" do
    asked = said("I will restart checkout. Approve?", calls: 1)
    @chat.request_decisions!(asked.ruby_llm_tool_calls.map(&:tool_call_id))
    @chat.decide!(asked.ruby_llm_tool_calls.sole.tool_call_id, approved: true)
    finished = said("Restarted.")

    assert_equal({ asked.id => Chat::TurnText::QUESTION, finished.id => Chat::TurnText::RESULT }, Chat::TurnText.roles([ asked.reload, finished ]))
  end

  test "a turn ends at the person's next message, so the next turn's calls never make the last words a status line" do
    answer = said("Checkout is fine.")
    @chat.add_message(role: :user, content: "And search?")
    said("Looking.", calls: 1)

    assert_equal Chat::TurnText::RESULT, Chat::TurnText.roles([ answer ])[answer.id]
  end

  test "Halon's notes to itself never end a turn" do
    first = said("Reading the deploys first.")
    @chat.nudge!("Take the read you offered.")
    said("", calls: 1)

    assert_equal Chat::TurnText::STATUS, Chat::TurnText.roles([ first ])[first.id]
  end

  test "a person's message and a message with no words have no role" do
    asked = @chat.add_message(role: :user, content: "Anything else?")
    empty = said("", calls: 1)

    assert_empty Chat::TurnText.roles([ asked, empty ])
  end

  private

  def said(text, calls: 0)
    message = @chat.add_message(role: :assistant, content: text)
    calls.times do
      @calls += 1
      RubyLLM::ActiveRecord::ToolCall.create!(message: message, tool_call_id: "call_#{@calls}", name: "github_list_review_comments", arguments: {})
    end
    message.reload
  end
end
