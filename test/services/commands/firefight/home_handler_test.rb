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

  test "opens home modal for empty command" do
    stub_open_modal
    command = build_command("")
    response = Commands::Firefight::HomeHandler.execute(command)

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
    response = Commands::Firefight::HomeHandler.execute(command)

    assert response[:success]
  end

  test "opens home modal for 'home' subcommand" do
    stub_open_modal
    command = build_command("home")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert response[:success]
  end

  test "handles trigger expiration for home modal" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError)
    command = build_command("")
    response = Commands::Firefight::HomeHandler.execute(command)

    assert_equal "ephemeral", response[:response_type]
    assert_includes response[:text], "expired"
  end

  # --- Placeholder subcommands ---

  test "routes 'summary' subcommand to SummaryHandler" do
    command = build_command("summary")

    Commands::Firefight::SummaryHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'lead' subcommand to LeadHandler" do
    command = build_command("lead")

    Commands::Firefight::LeadHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'status' subcommand to StatusHandler" do
    command = build_command("status")

    Commands::Firefight::StatusHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'update' subcommand to UpdateHandler" do
    command = build_command("update")

    Commands::Firefight::UpdateHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'severity' subcommand to SeverityHandler" do
    command = build_command("severity")

    Commands::Firefight::SeverityHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'escalate' subcommand to EscalateHandler" do
    command = build_command("escalate")

    Commands::Firefight::EscalateHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'list' subcommand to ListHandler" do
    command = build_command("list")

    Commands::Firefight::ListHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'timeline' subcommand to TimelineHandler" do
    command = build_command("timeline")

    Commands::Firefight::TimelineHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  %w[postmortem].each do |sub|
    test "handles '#{sub}' subcommand with placeholder" do
      command = build_command(sub)
      response = Commands::Firefight::HomeHandler.execute(command)

      assert_equal "ephemeral", response[:response_type]
      assert_includes response[:text], "coming soon"
    end
  end

  # --- Aliases ---

  test "routes 'action' to ActionsHandler" do
    command = build_command("action")

    Commands::Firefight::ActionsHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'actions' to ActionsHandler" do
    command = build_command("actions")

    Commands::Firefight::ActionsHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'followup' to FollowupsHandler" do
    command = build_command("followup")

    Commands::Firefight::FollowupsHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'followups' to FollowupsHandler" do
    command = build_command("followups")

    Commands::Firefight::FollowupsHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'resolve' to CloseHandler" do
    command = build_command("resolve")

    Commands::Firefight::CloseHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'close' to CloseHandler" do
    command = build_command("close")

    Commands::Firefight::CloseHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
  end

  test "routes 'reopen' to ReopenHandler" do
    command = build_command("reopen")

    Commands::Firefight::ReopenHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
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

    Commands::Firefight::SummaryHandler.expects(:execute).with(command).once

    Commands::Firefight::HomeHandler.execute(command)
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
