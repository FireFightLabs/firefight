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

  test "without the flag the old reply stands" do
    FeatureFlags.stubs(:enabled?).returns(false)

    assert_enqueued_with(job: IncidentAiResponseJob) { mention("what is going on") }

    assert_equal 0, @workspace.conversations.count
  end

  private

  def mention(text, thread_ts: "1700000000.000100", by: workspace_memberships(:alice_workspace_one))
    Events::AppMentionHandler.execute(@workspace, {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => Identifiers::EVENT_APP_MENTION, "channel" => @incident.channel_id,
        "user" => by.platform_user_id,
        "ts" => thread_ts, "text" => "<@U123> #{text}"
      }
    })
  end
end
