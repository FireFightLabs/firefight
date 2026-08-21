require "test_helper"

class CommandDispatcherTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships

  test "routes /firefight to Firefight::HomeHandler" do
    command = build_command(command_name: "/firefight", text: Identifiers::SUBCOMMAND_NEW)
    assert_equal Commands::HomeHandler, CommandDispatcher.find(command)
  end

  test "routes /ff to Firefight::HomeHandler" do
    command = build_command(command_name: "/ff", text: Identifiers::SUBCOMMAND_STATUS)
    assert_equal Commands::HomeHandler, CommandDispatcher.find(command)
  end

  test "routes /firefight with empty text to Firefight::HomeHandler" do
    command = build_command(command_name: "/firefight", text: "")
    assert_equal Commands::HomeHandler, CommandDispatcher.find(command)
  end

  test "falls back to DeclareIncident for unknown slash commands" do
    command = build_command(command_name: "/unknown", text: "")
    assert_equal Commands::DeclareIncident, CommandDispatcher.find(command)
  end

  test "falls back to DeclareIncident when no command name in metadata" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: "",
      channel_id: "C12345678",
      metadata: {}
    )
    assert_equal Commands::DeclareIncident, CommandDispatcher.find(command)
  end

  test "dispatch calls execute on the resolved handler" do
    membership = workspace_memberships(:bob_workspace_one)
    command = build_command(command_name: "/ff", text: Identifiers::SUBCOMMAND_SUMMARY)
    command.workspace_id = membership.workspace_id
    command.user_id = membership.platform_user_id

    Commands::HomeHandler.expects(:execute).with(command).once

    CommandDispatcher.dispatch(command)
  end

  test "dispatch authorizes the command the subcommand names, not the sub-dispatcher" do
    command = build_command(command_name: "/ff", text: Identifiers::SUBCOMMAND_CLOSE)
    assert_equal Commands::CloseIncident, CommandDispatcher.authorizing_handler(command)
  end

  test "dispatch refuses a member a subcommand they do not hold" do
    membership = workspace_memberships(:bob_workspace_one)
    command = build_command(command_name: "/ff", text: Identifiers::SUBCOMMAND_POSTMORTEM)
    command.workspace_id = membership.workspace_id
    command.user_id = membership.platform_user_id

    Commands::GeneratePostmortem.expects(:execute).never
    Commands::HomeHandler.expects(:execute).never
    WorkspaceMembership.any_instance.stubs(:implicitly_allowed?).returns(false)

    response = CommandDispatcher.dispatch(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_match(/don't have permission/, response[:text])
  end

  private

  def build_command(command_name:, text:)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: text,
      channel_id: "C12345678",
      metadata: { command: command_name }
    )
  end
end
