require "test_helper"

# A session someone opens in a tracker's issue is a chat like any other, acting as Firefight's own agent and answered in
# the issue.
class Conversation::IssueSessionsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear issue sync", settings: {})
    @row = @integration.integration_environments.create!
    @row.store_installation!("org-1")
    @said = []
    Integrations::AgentSessions::Linear.any_instance.stubs(:say).with { |session_id, activity| @said << [ session_id, activity ] }
    AppUrl.stubs(:options).returns(host: "ff.example.com", protocol: "https")
    Investigation.stubs(:unavailable_reason).returns(nil)
  end

  def event(kind, **fields)
    Integrations::AgentSessions::Event.new(kind: kind, session_id: "session-1", issue_key: "ENG-12", issue_title: "Checkout returns 500",
                                           issue_url: "https://linear.app/acme/issue/ENG-12", **fields)
  end

  def started(**fields)
    event(Integrations::AgentSessions::STARTED, text: "@firefight why is checkout failing?", context: "<issue identifier=\"ENG-12\"/>",
                                                asker_email: "ALICE@example.com", asker_name: "Alice", **fields)
  end

  def receive(event) = Conversation::IssueSessions.receive!(@row, event)

  def conversation = Conversation.in_issue_session(@integration, "session-1")

  test "a new session says Halon is on it first, then asks in a chat that acts as Firefight's agent, which no dashboard lists" do
    assert_enqueued_with(job: ConversationReplyJob) { receive(started) }

    assert_equal [ Integrations::AgentSessions::THOUGHT, Conversation::IssueSessions::ON_IT ], [ @said.first.last.kind, @said.first.last.body ]
    chat = conversation
    assert_equal [ Conversation::KIND_ISSUE, SystemAgent.investigator ], [ chat.kind, chat.started_by ]
    assert_equal "ENG-12 Checkout returns 500", chat.title
    assert_equal workspace_memberships(:alice_workspace_one), chat.issue_session.asked_by
    assert_not_includes Conversation.own_for(workspace_memberships(:alice_workspace_one)), chat

    person = chat.chat.messages.find_by!(role: Chat::Message::ROLE_USER, nudge: false)
    assert_equal "@firefight why is checkout failing?", person.content
    note = chat.chat.messages.find_by!(nudge: true)
    assert_match "started from an issue (ENG-12 https://linear.app/acme/issue/ENG-12)", note.content
    assert_match "trust=\"untrusted\"", note.content
    assert chat.answer_owed?
  end

  test "asking is in the activity log as Firefight's agent, naming who asked in the tracker" do
    receive(started)

    asked = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Action::INVESTIGATIONS_CREATE, principal_type: SystemAgent.name)
    assert_equal [ SystemAgent.investigator.id, "Alice in Linear" ], [ asked.principal_id, asked.triggered_by_label ]
  end

  test "a session opened by delegating the issue asks Halon to look into the issue itself" do
    receive(started(text: nil))

    assert_equal "Look into ENG-12 Checkout returns 500.", conversation.chat.messages.find_by!(role: Chat::Message::ROLE_USER, nudge: false).content
  end

  test "someone Firefight cannot match by email still gets an answer, and the chat is listed for nobody, admins included" do
    assert_enqueued_with(job: ConversationReplyJob) { receive(started(asker_email: "stranger@example.com")) }

    assert_nil conversation.issue_session.asked_by
    assert_not_includes Conversation.own_for(workspace_memberships(:alice_workspace_one)), conversation
    assert_not_includes Conversation.own_for(workspace_memberships(:bob_workspace_one)), conversation
  end

  test "a follow up carries on the same chat, and one sent while Halon works joins that turn" do
    receive(started)
    first = conversation

    receive(event(Integrations::AgentSessions::PROMPTED, text: "And payments?"))

    assert_equal first, conversation
    assert_equal 1, first.chat.queued_messages.waiting.count
    assert_equal "And payments?", first.chat.queued_messages.waiting.first.content
    assert_equal 2, @said.count { |_, activity| activity.kind == Integrations::AgentSessions::THOUGHT }
  end

  test "a follow up after the turn ended asks again in the same chat" do
    receive(started)
    conversation.reply_delivered!

    assert_enqueued_with(job: ConversationReplyJob) { receive(event(Integrations::AgentSessions::PROMPTED, text: "And payments?")) }

    assert_equal 2, conversation.chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).count
  end

  test "a session whose opening was missed starts from its first follow up" do
    receive(event(Integrations::AgentSessions::PROMPTED, text: "Still failing?"))

    assert_equal Conversation::KIND_ISSUE, conversation.kind
    assert_match "started from an issue", conversation.chat.messages.find_by!(nudge: true).content
  end

  test "stop asks the running turn to stop, and with nothing running says so" do
    receive(started)
    receive(event(Integrations::AgentSessions::STOPPED))
    assert conversation.chat.stop_requested?

    conversation.chat.clear_stop!
    conversation.reply_delivered!
    receive(event(Integrations::AgentSessions::STOPPED))

    assert_equal [ Integrations::AgentSessions::RESPONSE, Conversation::IssueSessions::NOTHING_TO_STOP ], [ @said.last.last.kind, @said.last.last.body ]
  end

  test "a workspace Halon cannot run in is told why in the issue, and no chat starts" do
    Investigation.stubs(:unavailable_reason).returns("AI features are not available.")

    assert_no_enqueued_jobs(only: ConversationReplyJob) { receive(started) }

    assert_equal [ Integrations::AgentSessions::ERROR, "AI features are not available." ], [ @said.last.last.kind, @said.last.last.body ]
    assert_nil conversation
  end


  test "a turn always acts as the agent, whoever pressed something for it in the dashboard" do
    receive(started)

    assert_equal SystemAgent.investigator, conversation.turn_asker(workspace_memberships(:alice_workspace_one).id)
  end

  # The turn paused on a call to confirm, as Chat::Tools leaves it.
  def paused_on_a_call
    receive(started)
    chat = conversation.chat
    asked = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    asked.ruby_llm_tool_calls.create!(tool_call_id: "call_9", name: "restart", arguments: {})
    chat.request_decisions!([ "call_9" ])
    conversation.reply_delivered!
    chat
  end

  def picked(word, email: "alice@example.com")
    event(Integrations::AgentSessions::PROMPTED, text: word, asker_email: email, asker_name: "Alice")
  end

  test "picking Confirm in the issue confirms the waiting call as the member who picked it, and the turn carries on as the agent" do
    chat = paused_on_a_call

    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id, workspace_memberships(:alice_workspace_one).id ]) { receive(picked("Confirm")) }

    assert_equal Chat::APPROVAL_APPROVED, chat.tool_calls.find_by!(tool_call_id: "call_9").approval
    assert_equal [ Integrations::AgentSessions::THOUGHT, Conversation::IssueSessions::GOING_AHEAD ], [ @said.last.last.kind, @said.last.last.body ]
    assert_equal SystemAgent.investigator, conversation.turn_asker(workspace_memberships(:alice_workspace_one).id)
    assert_equal 1, chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).count
    ledgered = Ability::Invocation.where(workspace: @workspace, action_key: Ability::Action::INVESTIGATIONS_CREATE, principal_type: WorkspaceMembership.name)
    assert_equal [ "Alice in Linear" ], ledgered.pluck(:triggered_by_label)
  end

  test "picking Skip skips it, and the turn carries on without it" do
    chat = paused_on_a_call

    assert_enqueued_with(job: ConversationReplyJob) { receive(picked("skip.")) }

    assert_equal Chat::APPROVAL_DENIED, chat.tool_calls.find_by!(tool_call_id: "call_9").approval
    assert_equal Conversation::IssueSessions::SKIPPED, @said.last.last.body
  end

  test "someone who matches no member, or may not ask Halon, is told the call still waits, with the choices again" do
    chat = paused_on_a_call

    assert_no_enqueued_jobs(only: ConversationReplyJob) { receive(picked("Confirm", email: "stranger@example.com")) }

    assert_equal Chat::APPROVAL_REQUESTED, chat.tool_calls.find_by!(tool_call_id: "call_9").approval
    told = @said.last.last
    assert_equal [ Integrations::AgentSessions::ELICITATION, [ "Confirm", "Skip" ] ], [ told.kind, told.choices ]
    assert_match "from the Linear account that uses the same email as theirs in Firefight", told.body

    AbilityGateway.stubs(:permitted?).returns(false)
    receive(picked("Confirm"))
    assert_equal Chat::APPROVAL_REQUESTED, chat.tool_calls.find_by!(tool_call_id: "call_9").approval
    assert_equal Integrations::AgentSessions::ELICITATION, @said.last.last.kind
  end

  test "Confirm with nothing waiting, or anything else said while a call waits, is a question like any other" do
    receive(started)
    conversation.reply_delivered!
    receive(picked("Confirm"))
    assert_equal "Confirm", conversation.chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).order(:created_at).last.content

    chat = paused_on_a_call
    receive(picked("Restart it, yes"))
    assert_equal Chat::APPROVAL_REQUESTED, chat.tool_calls.find_by!(tool_call_id: "call_9").approval
    assert_equal "Restart it, yes", chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).order(:created_at).last.content
  end
end
