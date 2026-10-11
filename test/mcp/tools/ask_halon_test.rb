require "test_helper"

class Mcp::Tools::AskHalonTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)
    Mcp::Tools::HalonAnswer.stubs(:pause)
  end

  test "a question is queued for the reply job and answered in the same call, as whoever the key belongs to" do
    asked_as = halon_replies("Two deploys went out.")

    response = perform_enqueued_jobs(only: ConversationReplyJob) { ask("What changed today?") }

    conversation = @workspace.conversations.sole
    assert_equal({ status: "answered", answer: "Two deploys went out.", conversation_id: conversation.id }, response.structured_content)
    assert_equal [ [ conversation, @member ] ], asked_as
    assert_performed_with(job: ConversationReplyJob, args: [ conversation.id, @member.id ], queue: "conversations")
  end

  test "an answer that takes longer than the wait says Halon is still working and how to fetch it, without holding the database" do
    Mcp::Tools::HalonAnswer.expects(:let_go_of_the_database).times(Mcp::Tools::HalonAnswer::WAIT / Mcp::Tools::HalonAnswer::LOOK_EVERY)

    response = ask("What changed today?")

    conversation = @workspace.conversations.sole
    assert_equal "working", response.structured_content[:status]
    assert_equal conversation.id, response.structured_content[:conversation_id]
    assert_equal "Halon is still working on this. Call get_halon_answer with this conversation_id to wait for the answer.",
                 response.structured_content[:answer]
    assert_not response.error?
    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id, @member.id ])
  end

  test "an answer that lands while the call waits is returned as soon as it is there" do
    halon_replies("Two deploys went out.")
    looks = 0
    Mcp::Tools::HalonAnswer.stubs(:pause).with do |_seconds|
      looks += 1
      perform_enqueued_jobs(only: ConversationReplyJob) if looks == 3
      true
    end

    response = ask("What changed today?")

    assert_equal "Two deploys went out.", response.structured_content[:answer]
    assert_equal 3, looks
  end

  test "a second question while Halon is still answering the first is refused with where to wait for it" do
    ask("What changed today?")
    conversation = @workspace.conversations.sole

    response = ask("And yesterday?")

    assert response.error?
    assert_equal "Halon is still answering your last question in this chat. Call get_halon_answer with conversation_id " \
                 "#{conversation.id} to wait for it, then ask again.", response.content.first[:text]
    assert_equal [ "What changed today?" ], conversation.chat.readable_messages.map(&:content)
    assert_enqueued_jobs 1, only: ConversationReplyJob
  end

  test "an AI account out of credit is said to the caller in plain words, and the chat no longer owes an answer" do
    Conversation::Runner.stubs(:new).returns(stub.tap { |runner| runner.stubs(:run).raises(FirefightAi::OutOfCredit.new("OpenRouter refused")) })

    response = perform_enqueued_jobs(only: ConversationReplyJob) { ask("What changed today?") }

    said = "Halon couldn't reach its AI just now."
    assert response.error?
    assert_equal said, response.content.sole[:text]
    conversation = @workspace.conversations.sole
    assert_not conversation.answer_owed?
    assert_equal said, conversation.chat.readable_messages.last.content
  end

  test "a turn whose job failed is an error with what the chat was told, and the next question answers as usual" do
    Conversation::Runner.stubs(:new).returns(stub.tap { |runner| runner.stubs(:run).raises(FirefightAi::TerminalError.new("bad request")) })

    failed = perform_enqueued_jobs(only: ConversationReplyJob) { ask("What changed today?") }

    assert failed.error?
    assert_equal Conversation::Delivery::FAILED, failed.content.sole[:text]
    assert @workspace.conversations.sole.reply_failed?

    halon_replies("Two deploys went out.")
    answered = perform_enqueued_jobs(only: ConversationReplyJob) { ask("Try again?") }

    assert_not answered.error?
    assert_equal "Two deploys went out.", answered.structured_content[:answer]
    assert_not @workspace.conversations.sole.reply_failed?
  end

  test "the chat is kept, so the next question from the same key carries on with it" do
    halon_replies("ok")

    perform_enqueued_jobs(only: ConversationReplyJob) do
      ask("one")
      ask("two")
    end

    conversation = @workspace.conversations.sole
    assert_equal Conversation::KIND_MCP, conversation.kind
    assert_equal @member, conversation.started_by
    assert_equal %w[one ok two ok], conversation.chat.readable_messages.map(&:content)
  end

  test "a service key or an agent gets a chat of its own, and its turn runs as itself" do
    key = api_keys(:full_access_key)
    asked_as = halon_replies("ok")

    perform_enqueued_jobs(only: ConversationReplyJob) do
      Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: key, args: { question: "who owns checkout?" })
    end

    assert_equal key, @workspace.conversations.sole.started_by
    assert_equal key, asked_as.sole.last
  end

  test "naming an incident puts the question in a chat about that incident, apart from the general one" do
    halon_replies("ok")
    incident = incidents(:active_critical_ws1)

    perform_enqueued_jobs(only: ConversationReplyJob) do
      ask("what changed?")
      ask("what is going on?", incident: incident.identifier)
      ask("and now?", incident: incident.identifier)
    end

    assert_equal [ nil, incident ], @workspace.conversations.order(:created_at).map(&:subject)
    assert_equal [ "what is going on?", "ok", "and now?", "ok" ], @workspace.conversations.find_by(subject: incident).chat.readable_messages.map(&:content)
  end

  test "a change that needs confirming is not left hanging, the caller is told what is waiting" do
    halon_replies { |conversation| pause_on_deleting_a_severity(conversation) }

    response = perform_enqueued_jobs(only: ConversationReplyJob) { ask("delete sev-4") }

    assert_equal "waiting", response.structured_content[:status]
    assert_match "Delete severity", response.structured_content[:waiting_on].sole
    assert_match "Confirm it in Firefight, then ask again.", response.structured_content[:answer]
  end

  test "an empty question is refused" do
    response = ask("  ")

    assert response.error?
    assert_no_enqueued_jobs
  end

  test "a workspace whose plan does not include AI says why" do
    message = deny_entitlements!

    response = ask("hi")

    assert response.error?
    assert_match message, response.content.first[:text]
  end

  private

  def ask(question, **args)
    Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: question, **args })
  end

  def pause_on_deleting_a_severity(conversation)
    chat = conversation.chat_record
    chat.add_message(RubyLLM::Message.new(
      role: :assistant, content: "",
      tool_calls: { "c1" => RubyLLM::ToolCall.new(id: "c1", name: Mcp::Tools::DELETE_SEVERITY, arguments: { "slug" => "sev-4" }) }
    ))
    chat.request_decisions!([ "c1" ])
  end
end
