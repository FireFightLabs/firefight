require "test_helper"

class Events::AppMentionHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper


  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "a mention opens Halon's conversation in the mention's thread" do
    stub_add_reaction

    assert_enqueued_with(job: ConversationReplyJob) do
      Events::AppMentionHandler.execute(@workspace, payload)
    end
    assert_equal "1234567890.123456", @workspace.conversations.sole.thread_id
  end

  test "strips bot mention from text" do
    stub_add_reaction

    Events::AppMentionHandler.execute(@workspace, payload(text: "<@U99999999> what's going on?"))

    asked = @workspace.conversations.sole.chat.messages.find_by!(role: Chat::Message::ROLE_USER)
    assert_equal "what's going on?", asked.content
  end

  test "reacts with eyes emoji on the message" do
    Slack::Client.expects(:add_reaction).with(
      workspace: @workspace,
      channel: @incident.channel_id,
      timestamp: "1234567890.123456",
      name: "eyes"
    ).once

    Events::AppMentionHandler.execute(@workspace, payload)
  end

  test "skips when no active incident in channel" do
    assert_no_enqueued_jobs do
      Events::AppMentionHandler.execute(@workspace, payload(channel: "C_NO_INCIDENT"))
    end
  end

  test "blocked entitlement posts the denial message and enqueues no job" do
    message = deny_entitlements!("Your trial has ended — upgrade to keep using AI.")
    Slack::Client.expects(:post_ephemeral).with(
      has_entries(workspace: @workspace, channel: @incident.channel_id, user: @member.platform_user_id, text: message)
    ).once

    assert_no_enqueued_jobs do
      Events::AppMentionHandler.execute(@workspace, payload)
    end
  end

  test "skips when text is empty after stripping mention" do
    assert_no_enqueued_jobs do
      Events::AppMentionHandler.execute(@workspace, payload(text: "<@U99999999>"))
    end
  end

  test "only Halon's own mention is taken out, and a person mentioned stays, read by Halon with their name and id" do
    stub_add_reaction
    bob = workspace_memberships(:bob_workspace_one)
    written = "ask <@#{bob.platform_user_id}> about <#C0123|deploys> :eyes:"

    Events::AppMentionHandler.execute(@workspace, payload(text: "<@U99999999|firefight> #{written}", app_user_id: "U99999999"))

    asked = @workspace.conversations.sole.chat.messages.find_by!(role: Chat::Message::ROLE_USER)
    assert_equal "ask @#{bob.display_name} (#{bob.platform_user_id}) about #deploys (C0123) 👀", asked.content
    assert_equal written, asked.as_written
  end

  test "when Slack does not say which mention is Halon's, the first one is, and the rest stay" do
    stub_add_reaction
    bob = workspace_memberships(:bob_workspace_one)

    Events::AppMentionHandler.execute(@workspace, payload(text: "<@U99999999> is <@#{bob.platform_user_id}> around?"))

    asked = @workspace.conversations.sole.chat.messages.find_by!(role: Chat::Message::ROLE_USER)
    assert_equal "is <@#{bob.platform_user_id}> around?", asked.as_written
  end

  test "a note added by mentioning Halon in a run's thread is read with names and ids, and kept as written" do
    stub_add_reaction
    bob = workspace_memberships(:bob_workspace_one)
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @member,
                                            max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_RUNNING, thread_id: "1690000000.000100")
    written = "ask <@#{bob.platform_user_id}>"

    Events::AppMentionHandler.execute(@workspace, payload(text: "<@U99999999> #{written}", app_user_id: "U99999999", thread: run.thread_id))

    assert_equal [ "ask @#{bob.display_name} (#{bob.platform_user_id})", written ], run.notes.sole.slice(:content, :as_written).values
  end

  private

  def payload(team_id: nil, channel: nil, text: nil, app_user_id: nil, thread: nil)
    {
      "team_id" => team_id || @workspace.platform_id,
      "authorizations" => ([ { "user_id" => app_user_id, "is_bot" => true } ] if app_user_id),
      "event" => {
        "type" => "app_mention",
        "user" => @member.platform_user_id,
        "text" => text || "<@U99999999> what's happening with this incident?",
        "ts" => "1234567890.123456",
        "thread_ts" => thread,
        "channel" => channel || @incident.channel_id
      }.compact
    }.compact
  end

  def stub_add_reaction
    Slack::Client.stubs(:add_reaction).returns({ ok: true })
  end
end
