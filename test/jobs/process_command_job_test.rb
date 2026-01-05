require "test_helper"
require "mocha/minitest"

class ProcessCommandJobTest < ActiveJob::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "should process valid slack command" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Use Mocha to verify CommandDispatcher.dispatch is called
    CommandDispatcher.expects(:dispatch).once
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
  end

  test "should parse slack payload into Command object" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Capture the command passed to dispatch
    dispatched_command = nil
    CommandDispatcher.stubs(:dispatch).with do |cmd|
      dispatched_command = cmd
      true
    end
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)

    assert_equal Platforms::SLACK, dispatched_command.platform
    assert_equal @workspace.id, dispatched_command.workspace_id
    assert_equal "U12345678", dispatched_command.user_id
    assert_equal "help", dispatched_command.text
  end

  test "should not dispatch invalid command" do
    payload = {
      "team_id" => "TNONEXIST", # Non-existent workspace
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Track if dispatch was called
    CommandDispatcher.expects(:dispatch).never
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
  end

  test "should handle commands with empty text" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    dispatched_command = nil
    CommandDispatcher.stubs(:dispatch).with do |cmd|
      dispatched_command = cmd
      true
    end
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)

    assert dispatched_command.blank?, "command should be blank for empty text"
  end

  test "should handle commands with text" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "status",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    dispatched_command = nil
    CommandDispatcher.stubs(:dispatch).with do |cmd|
      dispatched_command = cmd
      true
    end
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)

    assert_equal "status", dispatched_command.text
    assert_equal "status", dispatched_command.subcommand
  end

  test "should raise NotImplementedError for teams platform" do
    payload = {
      "team_id" => "some-teams-id",
      "user_id" => "some-user-id"
    }

    assert_raises(NotImplementedError) do
      ProcessCommandJob.perform_now(Platforms::TEAMS, payload)
    end
  end

  test "should raise ArgumentError for unknown platform" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678"
    }

    assert_raises(ArgumentError) do
      ProcessCommandJob.perform_now("unknown_platform", payload)
    end
  end

  test "should handle errors during command processing" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Simulate an error during dispatch
    CommandDispatcher.stubs(:dispatch).raises(StandardError, "Test error")
    # Mock Slack client to verify error notification is sent
    Slack::Client.stubs(:post_ephemeral).returns(nil)

    # Should not raise, error is caught
    assert_nothing_raised do
      ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end
  end

  test "should attempt to notify user when error occurs" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    notification_params = nil

    # Simulate an error during dispatch
    CommandDispatcher.stubs(:dispatch).raises(StandardError, "Test error")
    # Capture the notification call
    Slack::Client.stubs(:post_ephemeral).with do |args|
      notification_params = args
      true
    end

    ProcessCommandJob.perform_now(Platforms::SLACK, payload)

    assert_not_nil notification_params, "error notification should be sent"
    assert_equal @workspace, notification_params[:workspace]
    assert_equal "C12345678", notification_params[:channel]
    assert_equal "U12345678", notification_params[:user]
    assert_includes notification_params[:text], "Test error"
  end

  test "should handle error notification failure gracefully" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Simulate error during dispatch AND notification failure
    CommandDispatcher.stubs(:dispatch).raises(StandardError, "Test error")
    Slack::Client.stubs(:post_ephemeral).raises(StandardError, "Notification failed")

    # Should not raise, both errors are caught
    assert_nothing_raised do
      ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end
  end
end
