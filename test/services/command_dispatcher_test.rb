require "test_helper"

class CommandDispatcherTest < ActiveSupport::TestCase
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

  test "falls back to ModalHandler for unknown slash commands" do
    command = build_command(command_name: "/unknown", text: "")
    assert_equal Commands::ModalHandler, CommandDispatcher.find(command)
  end

  test "falls back to ModalHandler when no command name in metadata" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: SecureRandom.uuid,
      user_id: "U12345678",
      text: "",
      channel_id: "C12345678",
      metadata: {}
    )
    assert_equal Commands::ModalHandler, CommandDispatcher.find(command)
  end

  test "dispatch calls execute on the resolved handler" do
    command = build_command(command_name: "/ff", text: Identifiers::SUBCOMMAND_SUMMARY)

    Commands::HomeHandler.expects(:execute).with(command).once

    CommandDispatcher.dispatch(command)
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
