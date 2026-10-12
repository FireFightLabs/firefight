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
    @linked = []
    Integrations::AgentSessions::Linear.any_instance.stubs(:link).with { |session_id, label:, url:| @linked << [ session_id, label, url ] }
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

  test "a new session says Halon is on it first, then asks in a chat that acts as Firefight's agent and is listed for whoever asked" do
    assert_enqueued_with(job: ConversationReplyJob) { receive(started) }

    assert_equal [ Integrations::AgentSessions::THOUGHT, Conversation::IssueSessions::ON_IT ], [ @said.first.last.kind, @said.first.last.body ]
    chat = conversation
    assert_equal [ Conversation::KIND_ISSUE, SystemAgent.investigator ], [ chat.kind, chat.started_by ]
    assert_equal "ENG-12 Checkout returns 500", chat.title
    assert_equal workspace_memberships(:alice_workspace_one), chat.issue_session.asked_by
    assert_includes Conversation.own_for(workspace_memberships(:alice_workspace_one)), chat
    assert_equal [ [ "session-1", "Open in Firefight", Rails.application.routes.url_helpers.agent_chat_url(chat, host: "ff.example.com", protocol: "https") ] ], @linked

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

  test "someone Firefight cannot match by email is listed for the workspace's admins and nobody else" do
    receive(started(asker_email: "stranger@example.com"))

    assert_nil conversation.issue_session.asked_by
    assert_includes Conversation.own_for(workspace_memberships(:alice_workspace_one)), conversation
    assert_not_includes Conversation.own_for(workspace_memberships(:bob_workspace_one)), conversation
    assert_not_includes Conversation.own_for(nil), conversation
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

  test "the chat reads as asked in the tracker, with the issue to carry on in, and refuses to be asked on the dashboard" do
    receive(started)

    assert_equal "Linear", conversation.asked_in
    assert_equal "This chat is in Linear, so carry on there.", conversation.ask_blocked_reason
  end

  test "a turn always acts as the agent, whoever pressed something for it in the dashboard" do
    receive(started)

    assert_equal SystemAgent.investigator, conversation.turn_asker(workspace_memberships(:alice_workspace_one).id)
  end
end
