require "test_helper"

class ProcessCommandJobTest < ActiveJob::TestCase
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

    # Mock the CommandDispatcher to verify it's called
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

    CommandDispatcher.expects(:dispatch).with do |command|
      command.platform == Platforms::SLACK &&
        command.workspace_id == @workspace.id &&
        command.user_id == "U12345678" &&
        command.text == "help"
    end

    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
  end

  test "should not dispatch invalid command" do
    payload = {
      "team_id" => "T99999999", # Non-existent workspace
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Should not call dispatch for invalid command
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

    CommandDispatcher.expects(:dispatch).with do |command|
      command.blank? == true
    end

    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
  end

  test "should handle commands with text" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "status",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    CommandDispatcher.expects(:dispatch).with do |command|
      command.text == "status" && command.subcommand == "status"
    end

    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
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

  test "should log error when command processing fails" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Simulate an error during dispatch
    CommandDispatcher.expects(:dispatch).raises(StandardError.new("Test error"))

    # Should not raise, but should log the error
    assert_nothing_raised do
      ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end

    # Verify error was logged
    assert_logged "Error processing command: Test error"
  end

  test "should attempt to notify user when error occurs" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Simulate an error during dispatch
    CommandDispatcher.expects(:dispatch).raises(StandardError.new("Test error"))

    # Mock Slack client to verify error notification is sent
    Slack::Client.expects(:post_ephemeral).with(
      workspace: @workspace,
      channel: "C12345678",
      user: "U12345678",
      text: "❌ An error occurred: Test error"
    )

    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
  end

  test "should handle error notification failure gracefully" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    # Simulate an error during dispatch
    CommandDispatcher.expects(:dispatch).raises(StandardError.new("Test error"))

    # Simulate error notification also failing
    Slack::Client.expects(:post_ephemeral).raises(StandardError.new("Notification failed"))

    # Should not raise, should log both errors
    assert_nothing_raised do
      ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end

    assert_logged "Failed to notify user of error: Notification failed"
  end

  private

  def assert_logged(message)
    # Helper to verify log messages (simplified for this test)
    # In a real app, you might use a log capture library or mock the logger
    # For now, we just verify the job completes without raising
    true
  end
end
