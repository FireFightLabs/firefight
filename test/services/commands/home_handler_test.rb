require "test_helper"

class Commands::HomeHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  # --- Subcommand routing ---

  test "routes 'new' subcommand to DeclareIncident" do
    command = build_command("new")

    Commands::DeclareIncident.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  # --- Placeholder subcommands ---

  test "routes 'summary' subcommand to UpdateSummary" do
    command = build_command("summary")

    Commands::UpdateSummary.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'lead' subcommand to AssignLead" do
    command = build_command("lead")

    Commands::AssignLead.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'status' subcommand to ChangeStatus" do
    command = build_command("status")

    Commands::ChangeStatus.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'update' subcommand to UpdateIncident" do
    command = build_command("update")

    Commands::UpdateIncident.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'severity' subcommand to ChangeSeverity" do
    command = build_command("severity")

    Commands::ChangeSeverity.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'escalate' subcommand to EscalateIncident" do
    command = build_command("escalate")

    Commands::EscalateIncident.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'invite' subcommand to InviteResponders" do
    command = build_command("invite")

    Commands::InviteResponders.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'list' subcommand to ListActiveIncidents" do
    command = build_command("list")

    Commands::ListActiveIncidents.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'timeline' subcommand to ShowTimeline" do
    command = build_command("timeline")

    Commands::ShowTimeline.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "handles 'postmortem' subcommand" do
    command = build_command("postmortem")
    response = Commands::HomeHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "closed incident channel"
  end

  # --- Aliases ---

  test "routes 'action' to ListActions" do
    command = build_command("action")

    Commands::ListActions.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'actions' to ListActions" do
    command = build_command("actions")

    Commands::ListActions.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'followup' to ListFollowups" do
    command = build_command("followup")

    Commands::ListFollowups.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'followups' to ListFollowups" do
    command = build_command("followups")

    Commands::ListFollowups.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'resolve' to CloseIncident" do
    command = build_command("resolve")

    Commands::CloseIncident.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'close' to CloseIncident" do
    command = build_command("close")

    Commands::CloseIncident.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "routes 'reopen' to ReopenIncident" do
    command = build_command("reopen")

    Commands::ReopenIncident.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  # --- Unknown subcommand ---

  test "returns error for unknown subcommand" do
    command = build_command("notacommand")
    response = Commands::HomeHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "Unknown subcommand"
    assert_includes response[:text], "notacommand"
  end

  test "suggests closest match for typo subcommand" do
    command = build_command("reopn")
    response = Commands::HomeHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "Did you mean"
    assert_includes response[:text], "reopen"
  end

  test "returns generic message when no suggestion found" do
    command = build_command("xyzzy")
    response = Commands::HomeHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_includes response[:text], "Unknown subcommand"
    assert_not_includes response[:text], "Did you mean"
  end

  # --- Case insensitivity ---

  test "handles uppercase subcommands" do
    command = build_command("NEW")

    Commands::DeclareIncident.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  test "handles mixed case subcommands" do
    command = build_command("Summary")

    Commands::UpdateSummary.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  # --- Subcommand with extra args ---

  test "routes correctly when subcommand has additional arguments" do
    command = build_command("new production database down")

    Commands::DeclareIncident.expects(:execute).with(command).once

    Commands::HomeHandler.execute(command)
  end

  # --- Error handling ---

  test "returns error message when handler raises" do
    command = build_command("new")
    Commands::DeclareIncident.stubs(:execute).raises(StandardError, "boom")

    response = Commands::HomeHandler.execute(command)

    assert_equal Command::EPHEMERAL, response[:response_type]
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
