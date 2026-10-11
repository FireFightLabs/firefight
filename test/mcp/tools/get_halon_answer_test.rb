require "test_helper"

class Mcp::Tools::GetHalonAnswerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)
    Mcp::Tools::HalonAnswer.stubs(:pause)
  end

  test "an answer still being worked on is fetched once the reply job finishes it" do
    halon_replies("Two deploys went out.")
    conversation_id = call(Mcp::Tools::AskHalon, @member, question: "What changed today?").structured_content[:conversation_id]

    still = call(Mcp::Tools::GetHalonAnswer, @member, conversation_id: conversation_id)
    perform_enqueued_jobs(only: ConversationReplyJob)
    answered = call(Mcp::Tools::GetHalonAnswer, @member, conversation_id: conversation_id)

    assert_equal "working", still.structured_content[:status]
    assert_equal({ status: "answered", answer: "Two deploys went out.", conversation_id: conversation_id }, answered.structured_content)
  end

  test "a turn that paused on a confirmation is fetched as waiting, with what the person must confirm" do
    halon_replies do |conversation|
      chat = conversation.chat_record
      chat.add_message(RubyLLM::Message.new(
        role: :assistant, content: "",
        tool_calls: { "c1" => RubyLLM::ToolCall.new(id: "c1", name: Mcp::Tools::DELETE_SEVERITY, arguments: { "slug" => "sev-4" }) }
      ))
      chat.request_decisions!([ "c1" ])
    end
    conversation_id = call(Mcp::Tools::AskHalon, @member, question: "delete sev-4").structured_content[:conversation_id]
    perform_enqueued_jobs(only: ConversationReplyJob)

    fetched = call(Mcp::Tools::GetHalonAnswer, @member, conversation_id: conversation_id).structured_content

    assert_equal "waiting", fetched[:status]
    assert_match "Delete severity", fetched[:waiting_on].sole
  end

  test "a turn whose job was lost is fetched as an error with the sentence the recovery sweep left" do
    conversation_id = call(Mcp::Tools::AskHalon, @member, question: "What changed today?").structured_content[:conversation_id]
    conversation = @workspace.conversations.find(conversation_id)
    conversation.update!(answer_owed_since: 5.minutes.ago)

    Conversation::Recovery.sweep!(jobs: stub(waiting_or_running?: false, last_failed: nil))
    fetched = call(Mcp::Tools::GetHalonAnswer, @member, conversation_id: conversation_id)

    assert fetched.error?
    assert_equal Conversation::Recovery::INTERRUPTED, fetched.content.sole[:text]
  end

  test "only whoever asked can fetch the answer" do
    halon_replies("Two deploys went out.")
    conversation_id = perform_enqueued_jobs(only: ConversationReplyJob) do
      call(Mcp::Tools::AskHalon, @member, question: "What changed today?").structured_content[:conversation_id]
    end

    key = api_keys(:full_access_key)
    Ability::Grant.grant!(workspace: @workspace, principal: key, target: { action: Ability::Action.system!(Ability::Action::INVESTIGATIONS_CREATE) })

    [ workspace_memberships(:bob_workspace_one), key ].each do |someone_else|
      refused = call(Mcp::Tools::GetHalonAnswer, someone_else, conversation_id: conversation_id)
      assert refused.error?
      assert_equal "Not found in this workspace.", refused.content.sole[:text]
    end
  end

  test "a dashboard chat is never fetched through it, even by the person whose chat it is" do
    personal = Conversation.start_personal!(workspace: @workspace, member: @member)

    refused = call(Mcp::Tools::GetHalonAnswer, @member, conversation_id: personal.id)

    assert refused.error?
    assert_equal "Not found in this workspace.", refused.content.sole[:text]
  end

  test "it takes the permission to ask, so a key that may ask always gets its answer and one that may not is refused" do
    key = api_keys(:read_only_key)
    refused = call(Mcp::Tools::GetHalonAnswer, key, conversation_id: SecureRandom.uuid)
    assert_equal "This token lacks 'investigations:create' permission. Token scopes are documented at #{Mcp::Docs::MCP_SERVER}",
                 refused.content.sole[:text]

    Ability::Grant.grant!(workspace: @workspace, principal: key, target: { action: Ability::Action.system!(Ability::Action::INVESTIGATIONS_CREATE) })
    halon_replies("Two deploys went out.")
    conversation_id = call(Mcp::Tools::AskHalon, key, question: "What changed today?").structured_content[:conversation_id]
    perform_enqueued_jobs(only: ConversationReplyJob)

    assert_equal "Two deploys went out.", call(Mcp::Tools::GetHalonAnswer, key, conversation_id: conversation_id).structured_content[:answer]
  end

  private

  def call(tool, principal, **args)
    Mcp::ToolDispatcher.call(tool: tool, server_context: { workspace: @workspace, principal: principal }, args: args)
  end
end
