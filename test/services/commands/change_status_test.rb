require "test_helper"

class Commands::ChangeStatusTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities,
           :incident_forms, :incident_form_fields, :catalog_types, :incident_field_definitions, :incident_field_options

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens incident update modal in incident channel" do
    stub_post_message
    stub_open_modal

    result = Commands::ChangeStatus.execute(
      build_command(channel_id: @incident.channel_id)
    )

    assert_nil result
  end

  test "returns error when not in incident channel" do
    result = Commands::ChangeStatus.execute(
      build_command(channel_id: "C_NOT_INCIDENT")
    )

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "incident channel"
  end

  private

  def build_command(channel_id: "C12345678")
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_STATUS,
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end
