require "test_helper"

class Commands::GenerateCatchupTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "enqueues AI response job for active incident" do
    assert_enqueued_with(job: FirefightAi::IncidentResponseJob) do
      result = Commands::GenerateCatchup.execute(
        build_command(channel_id: @incident.channel_id)
      )
      assert_equal Command::EPHEMERAL, result[:response_type]
      assert_includes result[:text], "Generating catchup"
      assert_includes result[:text], @incident.identifier
    end
  end

  test "enqueues job with nil thread_ts for channel message" do
    Commands::GenerateCatchup.execute(
      build_command(channel_id: @incident.channel_id)
    )

    job = enqueued_jobs.find { |j| j["job_class"] == "FirefightAi::IncidentResponseJob" }
    assert_nil job["arguments"][2]
  end

  test "returns error when not in incident channel" do
    result = Commands::GenerateCatchup.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "active incident channel"
  end

  test "blocked entitlement returns the denial message and enqueues no job" do
    message = deny_entitlements!("Your trial has ended — upgrade to keep using AI.")

    assert_no_enqueued_jobs do
      result = Commands::GenerateCatchup.execute(build_command(channel_id: @incident.channel_id))
      assert_equal Command::EPHEMERAL, result[:response_type]
      assert_equal message, result[:text]
    end
  end

  private

  def build_command(channel_id: "C12345678")
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: @member.platform_user_id,
      text: Identifiers::SUBCOMMAND_CATCHUP,
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end
