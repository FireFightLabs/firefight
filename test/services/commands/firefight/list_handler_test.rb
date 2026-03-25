require "test_helper"

class Commands::Firefight::ListHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "returns active incidents sorted by severity then recency" do
    command = build_command

    response = Commands::Firefight::ListHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "*Active incidents*"
    assert_order response[:text], "*INC-004*", "*INC-002*"
    assert_includes response[:text], "<#C12345678>"
  end

  test "returns empty message when there are no active incidents" do
    @workspace.incidents.active.find_each do |incident|
      incident.update!(incident_status: incident_statuses(:resolved_ws1))
    end

    response = Commands::Firefight::ListHandler.execute(build_command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "no active incidents"
  end

  test "limits result set to 10 incidents" do
    18.times do |index|
      Incident.create!(
        workspace: @workspace,
        declared_by: @member,
        incident_status: incident_statuses(:investigating_ws1),
        incident_severity: incident_severities(:minor_ws1),
        sequence_number: 100 + index,
        identifier: "INC-#{100 + index}",
        name: "Generated incident #{index}",
        declared_at: (index + 1).minutes.ago,
        is_private: false,
        platform_data: {},
        custom_fields: {},
        source: Incident::SOURCE_SLACK
      )
    end

    response = Commands::Firefight::ListHandler.execute(build_command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "Showing 10 of"
    assert_equal 10, response[:text].lines.count { |line| line.start_with?("> *INC-") }
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_LIST,
      channel_id: "C12345678",
      metadata: { command: "/ff" }
    )

    response = Commands::Firefight::ListHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "Workspace not found"
  end

  private

  def build_command
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: @member.platform_user_id,
      text: Identifiers::SUBCOMMAND_LIST,
      channel_id: "CRANDOM",
      metadata: { command: "/ff" }
    )
  end

  def assert_order(text, first, second)
    assert_operator text.index(first), :<, text.index(second)
  end
end
