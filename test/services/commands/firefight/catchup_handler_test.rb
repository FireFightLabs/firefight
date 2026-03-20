require "test_helper"

class Commands::Firefight::CatchupHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "enqueues AI response job for active incident" do
    assert_enqueued_with(job: IncidentAiResponseJob) do
      result = Commands::Firefight::CatchupHandler.execute(
        build_command(channel_id: @incident.channel_id)
      )
      assert_equal Command::EPHEMERAL, result[:response_type]
      assert_includes result[:text], "Generating catchup"
      assert_includes result[:text], @incident.identifier
    end
  end

  test "enqueues job with nil thread_ts for channel message" do
    Commands::Firefight::CatchupHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    job = enqueued_jobs.find { |j| j["job_class"] == "IncidentAiResponseJob" }
    assert_nil job["arguments"][2]
  end

  test "returns error when not in incident channel" do
    result = Commands::Firefight::CatchupHandler.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "active incident channel"
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: @member.platform_user_id,
      text: Identifiers::SUBCOMMAND_CATCHUP,
      trigger_id: "12345.trigger",
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    result = Commands::Firefight::CatchupHandler.execute(command)

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "Workspace not found"
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
