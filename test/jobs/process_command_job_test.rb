require "test_helper"

class ProcessCommandJobTest < ActiveJob::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  # Helper method to stub class methods
  def stub_class_method(klass, method_name, stub_impl)
    original_method = klass.method(method_name)
    klass.define_singleton_method(method_name, stub_impl)
    yield
  ensure
    klass.define_singleton_method(method_name, original_method)
  end

  test "should process valid slack command" do
    payload = {
    "team_id" => @workspace.platform_id,
    "user_id" => "U12345678",
    "text" => "",
    "trigger_id" => "123456.789.abc123",
    "channel_id" => "C12345678"
    }

    # Verify CommandDispatcher.dispatch is called once
    dispatch_called = false
    stub_class_method(CommandDispatcher, :dispatch, ->(_cmd) { dispatch_called = true }) do
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end

    assert dispatch_called, "dispatch should be called"
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
    stub_class_method(CommandDispatcher, :dispatch, lambda { |cmd|
    dispatched_command = cmd
    nil
    }) do
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end

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
    dispatch_called = false
    stub_class_method(CommandDispatcher, :dispatch, lambda { |cmd|
    dispatch_called = true
    nil
    }) do
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end

    assert_equal false, dispatch_called, "dispatch should not be called for invalid workspace"
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
    stub_class_method(CommandDispatcher, :dispatch, lambda { |cmd|
    dispatched_command = cmd
    nil
    }) do
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end

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
    stub_class_method(CommandDispatcher, :dispatch, lambda { |cmd|
    dispatched_command = cmd
    nil
    }) do
    ProcessCommandJob.perform_now(Platforms::SLACK, payload)
    end

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
    stub_class_method(CommandDispatcher, :dispatch, lambda { |cmd| raise StandardError, "Test error" }) do
    stub_class_method(Slack::Client, :post_ephemeral, lambda { |args| nil }) do
      # Should not raise, error is caught
      assert_nothing_raised do
        ProcessCommandJob.perform_now(Platforms::SLACK, payload)
        end
      end
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

    # Simulate an error during dispatch and capture notification
    stub_class_method(CommandDispatcher, :dispatch, lambda { |cmd| raise StandardError, "Test error" }) do
    stub_class_method(Slack::Client, :post_ephemeral, lambda { |args|
      notification_params = args
      true
    }) do
      ProcessCommandJob.perform_now(Platforms::SLACK, payload)
      end
    end

    assert_not_nil notification_params, "error notification should be sent"
    assert_equal @workspace, notification_params[:workspace]
    assert_equal "C12345678", notification_params[:channel]
    assert_equal "U12345678", notification_params[:user]
    assert_equal "Sorry, something went wrong. Please try again.", notification_params[:text]
  end

  test "sends ephemeral response when handler returns one" do
    payload = {
    "team_id" => @workspace.platform_id,
    "user_id" => "U12345678",
    "text" => "summary",
    "trigger_id" => "123456.789.abc123",
    "channel_id" => "C12345678"
    }

    ephemeral_params = nil

    stub_class_method(CommandDispatcher, :dispatch, lambda { |_cmd|
    { response_type: Command::EPHEMERAL, text: "Not in incident channel" }
    }) do
    stub_class_method(Slack::Client, :post_ephemeral, lambda { |args|
      ephemeral_params = args
      { ok: true, ts: "123" }
    }) do
      ProcessCommandJob.perform_now(Platforms::SLACK, payload)
      end
    end

    assert_not_nil ephemeral_params, "ephemeral message should be posted"
    assert_equal "C12345678", ephemeral_params[:channel]
    assert_equal "U12345678", ephemeral_params[:user]
    assert_includes ephemeral_params[:text], "Not in incident channel"
  end

  test "passes ephemeral blocks when provided" do
    payload = {
    "team_id" => @workspace.platform_id,
    "user_id" => "U12345678",
    "text" => "timeline",
    "trigger_id" => "123456.789.abc123",
    "channel_id" => "C12345678"
    }

    ephemeral_params = nil

    stub_class_method(CommandDispatcher, :dispatch, lambda { |_cmd|
    {
      response_type: Command::EPHEMERAL,
      text: "Timeline",
      blocks: [ { type: "section", text: { type: "mrkdwn", text: "*Timeline*" } } ]
    }
    }) do
    stub_class_method(Slack::Client, :post_ephemeral, lambda { |args|
      ephemeral_params = args
      { ok: true, ts: "123" }
    }) do
      ProcessCommandJob.perform_now(Platforms::SLACK, payload)
      end
    end

    assert_not_nil ephemeral_params[:blocks]
    assert_equal "section", ephemeral_params[:blocks].first[:type]
  end

  test "does not send ephemeral when handler returns nil" do
    payload = {
    "team_id" => @workspace.platform_id,
    "user_id" => "U12345678",
    "text" => "summary",
    "trigger_id" => "123456.789.abc123",
    "channel_id" => "C12345678"
    }

    ephemeral_called = false

    stub_class_method(CommandDispatcher, :dispatch, lambda { |_cmd| nil }) do
    stub_class_method(Slack::Client, :post_ephemeral, lambda { |args|
      ephemeral_called = true
      { ok: true, ts: "123" }
    }) do
      ProcessCommandJob.perform_now(Platforms::SLACK, payload)
      end
    end

    assert_equal false, ephemeral_called, "ephemeral should not be sent when handler returns nil"
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
    stub_class_method(CommandDispatcher, :dispatch, lambda { |cmd| raise StandardError, "Test error" }) do
    stub_class_method(Slack::Client, :post_ephemeral, lambda { |args| raise StandardError, "Notification failed" }) do
      # Should not raise, both errors are caught
      assert_nothing_raised do
        ProcessCommandJob.perform_now(Platforms::SLACK, payload)
        end
      end
    end
  end
end
