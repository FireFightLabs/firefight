require "application_system_test_case"

# Halon read a deploy log that says web deploys from the release branch, while it remembered main. The chat asks which
# is right at once, says where the old memory came from, and an answer settles both memories with a toast.
class AgentMemoryQuestionCardTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("Why did the last web deploy ship an old build?")
    @conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "The deploy log shows web now ships from the release branch, not main.")
    @conversation.reply_delivered!
    @old = Chat::Memory.create!(workspace: @workspace, text: "web deploys from main", state: Chat::Memory::STATE_CONFIRMED, source: @conversation,
                                added_by: @alice, confirmed_by: @alice, confirmed_at: Time.zone.parse("2026-10-03 10:00"),
                                created_at: Time.zone.parse("2026-10-03 10:00"))
    @newer = Chat::Memory.learn!(@workspace, text: "web deploys from the release branch", subject: nil, source: @conversation,
                                             judge: judging(@old), contradiction: "The deploy log of web shows \"web deploys from the release branch\".").memory
    MemoryPostService.new(@workspace).ask_in_chat!(@conversation, @old.reload, evidence: "The deploy log of web shows \"web deploys from the release branch\".")
  end

  test "the chat asks which is right with where the memory came from, and Not right takes what Halon read instead" do
    visit agent_chat_path(@conversation)

    assert_text "Which is right?"
    assert_text "I used to remember \"web deploys from main\" (from your chat on Oct 3, 2026, confirmed by you). " \
                "The deploy log of web shows \"web deploys from the release branch\". Which is right?"
    assert_link "Open on the Memory page"

    click_on "Not right"

    assert_text "Marked not right. Halon now remembers \"web deploys from the release branch\" instead, confirmed by you."
    assert_text "Marked not right by you. Halon now remembers \"web deploys from the release branch\" instead."
    assert_no_button "Still right"
    assert_equal Chat::Memory::STATE_CONFIRMED, @newer.reload.state
  end

  test "Correct says what is right instead of both" do
    visit agent_chat_path(@conversation)

    click_on "Correct"
    fill_in "What is true", with: "web deploys from the release branch on weekdays and from main on Sundays"
    click_on "Save correction"

    assert_text "Corrected. Halon keeps the old wording as rejected so it does not learn it again."
    assert_equal Chat::Memory::STATE_REJECTED, @newer.reload.state
  end

  private

  def judging(memory)
    judge = Object.new
    judge.define_singleton_method(:verdicts) do |**|
      [ FirefightAi::MemoryJudge::Verdict.new(id: memory.id, verdict: FirefightAi::Schemas::MemoryVerdicts::CONTRADICTS) ]
    end
    judge
  end
end
