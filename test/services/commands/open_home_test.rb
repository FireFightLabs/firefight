require "test_helper"

class Commands::OpenHomeTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_severities, :incident_statuses, :incident_lifecycle_stages

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "opens home modal for empty command" do
    stub_open_modal
    command = build_command("")
    assert_nil Commands::OpenHome.execute(command)
  end

  test "opens home modal for nil text" do
    stub_open_modal
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: nil,
      channel_id: "C12345678",
      metadata: { command: "/ff" }
    )
    assert_nil Commands::OpenHome.execute(command)
  end

  test "opens home modal for 'home' subcommand" do
    stub_open_modal
    command = build_command(Identifiers::SUBCOMMAND_HOME)
    assert_nil Commands::OpenHome.execute(command)
  end

  private

  def build_command(text)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: text,
      trigger_id: "123456.789.abc123",
      channel_id: "C12345678",
      metadata: { command: "/ff" }
    )
  end
end
