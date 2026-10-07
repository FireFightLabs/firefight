require "test_helper"

class Events::AppMentionAgentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    Slack::Client.stubs(:add_reaction).returns({ ok: true })
  end

  test "a mention goes to the agent once AI SRE is on" do
    FeatureFlags.stubs(:enabled?).returns(true)

    assert_enqueued_with(job: ConversationReplyJob) { mention("what is going on") }

    conversation = @workspace.conversations.sole
    assert_equal @incident, conversation.subject
    assert_equal Conversation::KIND_CHANNEL, conversation.kind
    assert_equal "1700000000.000100", conversation.thread_id
  end

  test "a mention is told setup is not finished when the model's window is not known, rather than left with a spinner" do
    FeatureFlags.stubs(:enabled?).returns(true)
    FirefightAi.stubs(:context_window).returns(nil)
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:text].include?("not fully set up") }.returns({ ok: true })

    assert_no_enqueued_jobs(only: ConversationReplyJob) { mention("what is going on") }
  end

  test "each mention acts as whoever tagged the agent, not whoever started the thread" do
    FeatureFlags.stubs(:enabled?).returns(true)
    bob = workspace_memberships(:bob_workspace_one)
    mention("what is going on")

    assert_enqueued_with(job: ConversationReplyJob, args: [ @workspace.conversations.sole.id, bob.id ]) do
      mention("and who is leading", by: bob)
    end
  end

  test "a second mention in the same thread joins the conversation already there" do
    FeatureFlags.stubs(:enabled?).returns(true)

    mention("what is going on")
    mention("and who is leading")

    assert_equal 1, @workspace.conversations.count
  end

  test "a mention that starts with investigate starts a run with the rest as its brief, and opens no chat" do
    FeatureFlags.stubs(:enabled?).returns(true)

    assert_enqueued_with(job: InvestigationJob) { mention("investigate checkout 500s since 2pm") }

    investigation = @incident.investigations.live.sole
    assert_equal "checkout 500s since 2pm", investigation.brief[Investigation::Brief::KEY_SYMPTOM]
    assert_equal workspace_memberships(:alice_workspace_one), investigation.triggered_by
    assert_equal 0, @workspace.conversations.count
  end

  test "investigate later in the message is a question, answered in the chat" do
    FeatureFlags.stubs(:enabled?).returns(true)

    assert_enqueued_with(job: ConversationReplyJob) { mention("should we investigate the cache first?") }

    assert_empty @incident.investigations
  end

  test "a run that cannot start says why to the person who asked, and only to them" do
    FeatureFlags.stubs(:enabled?).returns(true)
    mention("investigate")
    Slack::Client.expects(:post_ephemeral).with do |arguments|
      arguments[:user] == workspace_memberships(:alice_workspace_one).platform_user_id && arguments[:text].include?("Already investigating")
    end.returns({ ok: true })

    mention("Investigate again")
  end

  test "files shared with a mention are downloaded through Slack and go with the question" do
    FeatureFlags.stubs(:enabled?).returns(true)
    graph = file_fixture("halon_graph.png").binread
    Slack::Client.expects(:download_file).with { |arguments| arguments[:url].end_with?("graph.png") }.returns({ body: graph, content_type: "image/png" })
    Slack::Client.expects(:download_file).with { |arguments| arguments[:url].end_with?("app.log") }.returns({ body: "boom at 10:02", content_type: "text/plain" })

    mention("what broke?", files: [ slack_file("F1", "graph.png", size: graph.bytesize), slack_file("F2", "app.log", size: 13) ])

    message = @workspace.conversations.sole.chat.messages.find_by!(role: Chat::Message::ROLE_USER)
    assert_equal %w[graph.png app.log], message.attached_files.map(&:filename)
    assert_equal workspace_memberships(:alice_workspace_one), message.attached_files.first.uploaded_by
    handed = message.to_llm
    assert_equal 1, handed.attachments.size
    assert_match "boom at 10:02", handed.content
  end

  test "a file shared with only a mention and no words is still a question" do
    FeatureFlags.stubs(:enabled?).returns(true)
    Slack::Client.stubs(:download_file).returns({ body: "boom", content_type: "text/plain" })

    assert_enqueued_with(job: ConversationReplyJob) { mention("", files: [ slack_file("F1", "app.log", size: 4) ]) }
  end

  test "a file Halon does not read, one too large and one Slack would not hand over are kept with why, so Halon says so" do
    FeatureFlags.stubs(:enabled?).returns(true)
    Slack::Client.stubs(:download_file).with { |arguments| arguments[:url].end_with?("dump.zip") }.returns({ body: "PK\u0003\u0004\u0000\u0000".b, content_type: "application/zip" })
    Slack::Client.stubs(:download_file).with { |arguments| arguments[:url].end_with?("locked.log") }
      .raises(AdapterError, "Slack file download returned HTML, bot may be missing files:read scope")

    mention("look", files: [
      slack_file("F1", "dump.zip", size: 6),
      slack_file("F2", "huge.log", size: Chat::Attachment::LARGEST + 1),
      slack_file("F3", "locked.log", size: 10)
    ])

    files = @workspace.conversations.sole.chat.attached_files.to_a
    assert files.all?(&:unread?)
    handed = @workspace.conversations.sole.chat.messages.find_by!(role: Chat::Message::ROLE_USER).to_llm.content
    assert_match "[dump.zip was not read. dump.zip is not a file Halon reads. #{Chat::Attachment::ACCEPTED} Tell the person plainly.]", handed
    assert_match "huge.log is 10 MB, and Halon reads a file up to 10 MB.", handed
    assert_match Slack::WorkspaceAdapter::FileOperations::NO_PERMISSION, handed
  end

  test "files past the limit for one message are named and not read" do
    FeatureFlags.stubs(:enabled?).returns(true)
    Slack::Client.stubs(:download_file).returns({ body: "ok", content_type: "text/plain" })
    files = (1..(Chat::Attachment::MAX_PER_MESSAGE + 1)).map { |number| slack_file("F#{number}", "#{number}.log", size: 2) }

    mention("look", files: files)

    attached = @workspace.conversations.sole.chat.attached_files.to_a
    assert_equal Chat::Attachment::MAX_PER_MESSAGE, attached.count { |file| !file.unread? }
    assert_equal Chat::Attachment::TOO_MANY, attached.last.refusal
  end

  test "without the flag the old reply stands" do
    FeatureFlags.stubs(:enabled?).returns(false)

    assert_enqueued_with(job: IncidentAiResponseJob) { mention("what is going on") }

    assert_equal 0, @workspace.conversations.count
  end

  test "outside an incident's channel a mention that starts with investigate investigates the question there" do
    FeatureFlags.stubs(:enabled?).returns(true)

    assert_enqueued_with(job: InvestigationJob) { mention("investigate billing is slow", channel: "C0GENERAL") }

    investigation = @workspace.investigations.find_by!(channel_id: "C0GENERAL")
    assert_nil investigation.subject
    assert_equal "billing is slow", investigation.question
  end

  test "with AI SRE off, a mention outside an incident's channel is left alone, investigate or not" do
    FeatureFlags.stubs(:enabled?).returns(false)
    Slack::Client.expects(:add_reaction).never

    assert_no_enqueued_jobs { mention("investigate billing is slow", channel: "C0GENERAL") }
    assert_equal 0, @workspace.investigations.count
  end

  test "outside an incident's channel any other mention is left alone" do
    FeatureFlags.stubs(:enabled?).returns(true)

    assert_no_enqueued_jobs { mention("what is going on", channel: "C0GENERAL") }
  end

  test "a mention in a running investigation's thread is added to the run, and opens no chat" do
    FeatureFlags.stubs(:enabled?).returns(true)
    run = running_investigation

    assert_no_enqueued_jobs(only: ConversationReplyJob) do
      mention("skip GitHub, look at 5xx on web", thread_ts: "1700000000.000950", parent: run.thread_id)
    end

    assert_equal "skip GitHub, look at 5xx on web", run.notes.sole.content
    assert_equal workspace_memberships(:alice_workspace_one), run.notes.sole.sender
    assert_equal 0, @workspace.conversations.count
  end

  test "a mention in a finished investigation's thread is answered as a chat, as before" do
    FeatureFlags.stubs(:enabled?).returns(true)
    run = running_investigation(status: Investigation::STATUS_SUCCEEDED)

    assert_enqueued_with(job: ConversationReplyJob) { mention("why was that", thread_ts: "1700000000.000950", parent: run.thread_id) }
  end

  test "someone who may not start an investigation is told, and nothing is added" do
    FeatureFlags.stubs(:enabled?).returns(true)
    run = running_investigation
    AbilityGateway.stubs(:authorize!).raises(AbilityGateway::Denied.new("investigations.create"))
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:text].include?("may not add to an investigation") }.returns({ ok: true })

    mention("skip GitHub", thread_ts: "1700000000.000950", parent: run.thread_id)

    assert_empty run.notes
  end

  test "a member asks Halon and starts an investigation without any grant" do
    FeatureFlags.stubs(:enabled?).returns(true)
    bob = workspace_memberships(:bob_workspace_one)

    assert_enqueued_with(job: ConversationReplyJob) { mention("what is going on", by: bob) }
    assert_enqueued_with(job: InvestigationJob) { mention("investigate checkout 500s", thread_ts: "1700000000.000200", by: bob) }

    assert_equal bob, @incident.investigations.live.sole.triggered_by
  end

  test "a member an admin took asking away from is told so, only them, and nothing is asked or started" do
    FeatureFlags.stubs(:enabled?).returns(true)
    bob = workspace_memberships(:bob_workspace_one)
    take_halon_from(@workspace, bob)
    refusal = AuthorizedDispatch.denied_message(AbilityGateway::Denied.new(Ability::Action::INVESTIGATIONS_CREATE))
    Slack::Client.expects(:post_ephemeral).with { |arguments| arguments[:user] == bob.platform_user_id && arguments[:text] == refusal }
                 .twice.returns({ ok: true })

    assert_no_enqueued_jobs(only: [ ConversationReplyJob, InvestigationJob ]) do
      mention("what is going on", by: bob)
      mention("investigate checkout 500s", thread_ts: "1700000000.000200", by: bob)
    end
    assert_equal 0, @workspace.conversations.count
    assert_empty @incident.investigations
    assert_equal Ability::Invocation::DECISION_DENY,
                 @workspace.ability_invocations.find_by!(principal_id: bob.id, source: AbilityGateway::SOURCE_SLACK,
                                                         action_key: Ability::Action::INVESTIGATIONS_CREATE).decision
  end

  test "a question to Halon in Slack is in Activity as whoever asked, and an approval rule never holds it" do
    FeatureFlags.stubs(:enabled?).returns(true)
    bob = workspace_memberships(:bob_workspace_one)
    @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals").policy_rules.create!(
      priority: 1,
      conditions: [ { field: PolicyRule::ApprovalConditions::FIELD_ACTION_KEY, operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ Ability::Action::INVESTIGATIONS_CREATE ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )
    halon = Ability::Action.system!(Ability::Action::INVESTIGATIONS_CREATE)
    assert AbilityGateway.approval_requirement(@workspace, halon, halon.key, {}, {}), "the rule would hold the dashboard"

    assert_enqueued_with(job: ConversationReplyJob) { mention("what is going on", by: bob) }

    asked = @workspace.ability_invocations.find_by!(principal_id: bob.id, action_key: Ability::Action::INVESTIGATIONS_CREATE)
    assert_equal [ Ability::Invocation::DECISION_ALLOW, AbilityGateway::SOURCE_SLACK, @incident.id ], [ asked.decision, asked.source, asked.incident_id ]
    assert asked.completed_at
    assert_empty @workspace.ability_approvals
  end

  private

  def mention(text, thread_ts: "1700000000.000100", by: workspace_memberships(:alice_workspace_one), channel: @incident.channel_id, parent: nil, files: nil)
    Events::AppMentionHandler.execute(@workspace, {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => Identifiers::EVENT_APP_MENTION, "channel" => channel,
        "user" => by.platform_user_id,
        "ts" => thread_ts, "thread_ts" => parent, "text" => "<@U123> #{text}", "files" => files
      }.compact
    })
  end

  def slack_file(id, name, size:, url: "https://files.slack.com/files-pri/T1-#{id}/download/#{name}")
    { "id" => id, "name" => name, "mimetype" => "application/octet-stream", "size" => size, "url_private_download" => url }
  end

  def running_investigation(status: Investigation::STATUS_RUNNING)
    @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
      max_turns: 10, max_spend_cents: 400, thread_id: "1700000000.000900", status: status
    )
  end
end
