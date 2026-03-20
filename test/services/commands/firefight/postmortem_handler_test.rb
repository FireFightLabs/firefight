require "test_helper"

class Commands::Firefight::PostmortemHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @resolved_status = incident_statuses(:resolved_ws1)
    @severity = incident_severities(:critical_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @resolved_status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_CLOSED_INCIDENT",
      resolved_at: 1.hour.ago
    )
  end

  test "enqueues postmortem generation for closed incident" do
    assert_enqueued_with(job: PostmortemGenerationJob) do
      result = Commands::Firefight::PostmortemHandler.execute(
        build_command(channel_id: @incident.channel_id)
      )
      assert_equal Command::EPHEMERAL, result[:response_type]
      assert_includes result[:text], "Generating postmortem"
      assert_includes result[:text], @incident.identifier
    end
  end

  test "returns error when not in closed incident channel" do
    result = Commands::Firefight::PostmortemHandler.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "closed incident channel"
  end

  test "returns error when incident is active not closed" do
    result = Commands::Firefight::PostmortemHandler.execute(
      build_command(channel_id: "C12345678")
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "closed incident channel"
  end

  test "returns error when postmortem already exists" do
    Postmortem.create!(
      incident: @incident,
      generated_by: @member,
      title: "Existing",
      content: { "sections" => [] }
    )

    result = Commands::Firefight::PostmortemHandler.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "already been generated"
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: @member.platform_user_id,
      text: Identifiers::SUBCOMMAND_POSTMORTEM,
      trigger_id: "12345.trigger",
      channel_id: @incident.channel_id,
      metadata: { command: "/ff" }
    )

    result = Commands::Firefight::PostmortemHandler.execute(command)

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "Workspace not found"
  end

  private

  def build_command(channel_id: "C12345678")
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: @member.platform_user_id,
      text: Identifiers::SUBCOMMAND_POSTMORTEM,
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end
