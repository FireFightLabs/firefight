require "test_helper"

class Commands::Firefight::HomeModalHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "opens home modal for empty command" do
    stub_open_modal
    command = build_command("")
    response = Commands::Firefight::HomeModalHandler.execute(command)

    assert response[:success]
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
    response = Commands::Firefight::HomeModalHandler.execute(command)

    assert response[:success]
  end

  test "opens home modal for 'home' subcommand" do
    stub_open_modal
    command = build_command(Identifiers::SUBCOMMAND_HOME)
    response = Commands::Firefight::HomeModalHandler.execute(command)

    assert response[:success]
  end

  test "handles trigger expiration" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError)
    command = build_command("")
    response = Commands::Firefight::HomeModalHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "expired"
  end

  test "returns error when workspace not found" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: "",
      channel_id: "C12345678",
      metadata: { command: "/ff" }
    )
    response = Commands::Firefight::HomeModalHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "Workspace not found"
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
