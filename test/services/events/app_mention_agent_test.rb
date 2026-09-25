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

  private

  def mention(text, thread_ts: "1700000000.000100", by: workspace_memberships(:alice_workspace_one), channel: @incident.channel_id, parent: nil)
    Events::AppMentionHandler.execute(@workspace, {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => Identifiers::EVENT_APP_MENTION, "channel" => channel,
        "user" => by.platform_user_id,
        "ts" => thread_ts, "thread_ts" => parent, "text" => "<@U123> #{text}"
      }.compact
    })
  end

  def running_investigation(status: Investigation::STATUS_RUNNING)
    @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
      max_turns: 10, max_spend_cents: 400, thread_id: "1700000000.000900", status: status
    )
  end
end
