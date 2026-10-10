require "test_helper"

class Chat::TerminalSessionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @turn = Conversation::Turn.new(@conversation, asker: @member)
  end

  test "the token is kept only as a digest, reaches its session while it lasts, and nothing once the command ended" do
    session, token = Chat::TerminalSession.open!(@turn, changes: true, lasts: 60.seconds)

    assert_not_equal token, session.token_digest
    assert_equal session, Chat::TerminalSession.authenticate(token)
    assert session.changes_allowed
    assert_equal [ @conversation, @member ], [ session.agent_run.conversation, session.agent_run.asker ]

    session.finish!
    assert_nil Chat::TerminalSession.authenticate(token)
  end

  test "a token past its time reaches nothing, and an old row is cleared when the next command starts" do
    session, token = Chat::TerminalSession.open!(@turn, changes: false, lasts: 60.seconds)
    session.update_columns(expires_at: 2.days.ago)

    assert_nil Chat::TerminalSession.authenticate(token)
    Chat::TerminalSession.open!(@turn, changes: false, lasts: 60.seconds)
    assert_not Chat::TerminalSession.exists?(session.id)
  end

  test "a run that only reads never allows changes, and an investigation's calls are made as the investigation" do
    watching = Conversation::Turn.new(@conversation, asker: @member, reads_only: true)
    assert_not Chat::TerminalSession.open!(watching, changes: true, lasts: 60.seconds).first.changes_allowed

    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)
    session, = Chat::TerminalSession.open!(investigation, changes: true, lasts: 60.seconds)
    assert_equal [ false, nil, investigation ], [ session.changes_allowed, session.principal, session.agent_run ]
  end

  test "calls are counted in SQL up to the most one command may make" do
    session, = Chat::TerminalSession.open!(@turn, changes: false, lasts: 60.seconds)
    session.update_columns(calls: Chat::TerminalSession::MAX_CALLS - 1)

    assert session.count_call!
    assert_not session.count_call!
  end
end
