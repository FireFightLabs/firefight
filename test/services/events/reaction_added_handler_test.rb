require "test_helper"

class Events::ReactionAddedHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT"
    )
  end

  test "posts action prompt for boom reaction in incident channel" do
    stub_get_message(text: "The database is slow")
    stub_get_permalink
    stub_post_ephemeral

    Slack::Client.expects(:post_ephemeral).once.returns({ ok: true, ts: "1234567890.123456" })

    Events::ReactionAddedHandler.execute(Platforms::SLACK, build_payload(reaction: "boom"))
  end

  test "posts followup prompt for arrow_forward reaction" do
    stub_get_message(text: "We should add monitoring")
    stub_get_permalink
    stub_post_ephemeral

    Slack::Client.expects(:post_ephemeral).once.returns({ ok: true, ts: "1234567890.123456" })

    Events::ReactionAddedHandler.execute(Platforms::SLACK, build_payload(reaction: "arrow_forward"))
  end

  test "ignores non-action reactions" do
    Slack::Client.expects(:post_ephemeral).never

    Events::ReactionAddedHandler.execute(Platforms::SLACK, build_payload(reaction: "thumbsup"))
  end

  test "ignores reactions in non-incident channels" do
    Slack::Client.expects(:post_ephemeral).never

    payload = build_payload(reaction: "boom", channel: "C_NOT_INCIDENT")
    Events::ReactionAddedHandler.execute(Platforms::SLACK, payload)
  end

  test "ignores reactions from unknown workspace" do
    Slack::Client.expects(:post_ephemeral).never

    payload = build_payload(reaction: "boom")
    payload["team_id"] = "T_UNKNOWN"
    Events::ReactionAddedHandler.execute(Platforms::SLACK, payload)
  end

  private

  def build_payload(reaction:, channel: nil)
    {
      "team_id" => @workspace.platform_id,
      "event" => {
        "type" => "reaction_added",
        "user" => @member.platform_user_id,
        "reaction" => reaction,
        "item" => {
          "type" => "message",
          "channel" => channel || @incident.channel_id,
          "ts" => "1234567890.111111"
        }
      }
    }
  end
end
