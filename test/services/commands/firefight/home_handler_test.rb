require "test_helper"

class Commands::Firefight::HomeHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  # --- Subcommand routing ---

  test "routes 'new' subcommand to ModalHandler" do
    command = build_command("new")

    Commands::ModalHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "handles empty command as home" do
    command = build_command("")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Incident Home"
  end

  test "handles nil text as home" do
    command = Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: nil,
      channel_id: "C12345678",
      metadata: { command: "/ff" }
    )
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Incident Home"
  end

  test "handles 'home' subcommand" do
    command = build_command("home")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Incident Home"
  end

  # --- Placeholder subcommands ---

  %w[summary lead status severity escalate timeline list postmortem].each do |sub|
    test "handles '#{sub}' subcommand with placeholder" do
      command = build_command(sub)
      response = Commands::Firefight::HomeHandler.execute(command)

      assert_equal "ephemeral", response[:response_type]
      assert_includes response[:text], "coming soon"
    end
  end

  # --- Aliases ---

  test "handles 'action' alias for 'actions'" do
    command = build_command("action")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Actions"
  end

  test "handles 'actions' subcommand" do
    command = build_command("actions")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Actions"
  end

  test "handles 'resolve' alias for 'close'" do
    command = build_command("resolve")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Close"
  end

  test "handles 'close' subcommand" do
    command = build_command("close")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Close"
  end

  # --- Unknown subcommand ---

  test "returns error for unknown subcommand" do
    command = build_command("notacommand")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "Unknown subcommand"
    assert_includes response[:text], "notacommand"
  end

  # --- Case insensitivity ---

  test "handles uppercase subcommands" do
    command = build_command("NEW")

    Commands::ModalHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "handles mixed case subcommands" do
    command = build_command("Summary")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "coming soon"
  end

  # --- Subcommand with extra args ---

  test "routes correctly when subcommand has additional arguments" do
    command = build_command("new production database down")

    Commands::ModalHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  # --- Error handling ---

  test "returns error message when handler raises" do
    command = build_command("new")
    Commands::ModalHandler.stubs(:execute).raises(StandardError, "boom")

    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "something went wrong"
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
