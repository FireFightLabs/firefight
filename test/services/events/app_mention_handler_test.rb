require "test_helper"

class Events::AppMentionHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "enqueues AI response job for valid mention" do
    stub_add_reaction

    assert_enqueued_with(job: IncidentAiResponseJob) do
      Events::AppMentionHandler.execute(Platforms::SLACK, payload)
    end
  end

  test "passes thread_ts as the mention message ts" do
    stub_add_reaction

    Events::AppMentionHandler.execute(Platforms::SLACK, payload)

    job = enqueued_jobs.find { |j| j["job_class"] == "IncidentAiResponseJob" }
    assert_equal "1234567890.123456", job["arguments"][2]
  end

  test "strips bot mention from text" do
    stub_add_reaction

    Events::AppMentionHandler.execute(Platforms::SLACK, payload(text: "<@U99999999> what's going on?"))

    job = enqueued_jobs.find { |j| j["job_class"] == "IncidentAiResponseJob" }
    assert_equal "what's going on?", job["arguments"][3]
  end

  test "reacts with eyes emoji on the message" do
    Slack::Client.expects(:add_reaction).with(
      workspace: @workspace,
      channel: @incident.channel_id,
      timestamp: "1234567890.123456",
      name: "eyes"
    ).once

    Events::AppMentionHandler.execute(Platforms::SLACK, payload)
  end

  test "skips when workspace not found" do
    assert_no_enqueued_jobs do
      Events::AppMentionHandler.execute(Platforms::SLACK, payload(team_id: "T_UNKNOWN"))
    end
  end

  test "skips when no active incident in channel" do
    assert_no_enqueued_jobs do
      Events::AppMentionHandler.execute(Platforms::SLACK, payload(channel: "C_NO_INCIDENT"))
    end
  end

  test "skips when text is empty after stripping mention" do
    assert_no_enqueued_jobs do
      Events::AppMentionHandler.execute(Platforms::SLACK, payload(text: "<@U99999999>"))
    end
  end

  test "strips multiple mention formats" do
    assert_equal "hello world", Events::AppMentionHandler.send(:strip_mention, "<@U123> hello <@U456|bob> world")
  end

  test "strips mention with username format" do
    assert_equal "what's up?", Events::AppMentionHandler.send(:strip_mention, "<@U123|firefight> what's up?")
  end

  private

  def payload(team_id: nil, channel: nil, text: nil)
    {
      "team_id" => team_id || @workspace.platform_id,
      "event" => {
        "type" => "app_mention",
        "user" => @member.platform_user_id,
        "text" => text || "<@U99999999> what's happening with this incident?",
        "ts" => "1234567890.123456",
        "channel" => channel || @incident.channel_id
      }
    }
  end

  def stub_add_reaction
    Slack::Client.stubs(:add_reaction).returns({ ok: true })
  end
end
