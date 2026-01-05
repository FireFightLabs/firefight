require "test_helper"

class Slack::CommandAdapterTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "parse creates Command object from Slack payload" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help me",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678",
      "team_domain" => "test-workspace",
      "channel_name" => "general",
      "user_name" => "alice",
      "command" => "/firefight",
      "response_url" => "https://hooks.slack.com/commands/T12345678/12345/abc123"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert_equal Platforms::SLACK, command.platform
    assert_equal @workspace.id, command.workspace_id
    assert_equal "U12345678", command.user_id
    assert_equal "help me", command.text
    assert_equal "123456.789.abc123", command.trigger_id
    assert_equal "C12345678", command.channel_id
  end

  test "parse stores platform-specific data in metadata" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678",
      "team_domain" => "test-workspace",
      "channel_name" => "general",
      "user_name" => "alice",
      "command" => "/firefight",
      "response_url" => "https://hooks.slack.com/commands/T12345678/12345/abc123"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert_equal @workspace.platform_id, command.metadata[:team_id]
    assert_equal "test-workspace", command.metadata[:team_domain]
    assert_equal "general", command.metadata[:channel_name]
    assert_equal "alice", command.metadata[:user_name]
    assert_equal "/firefight", command.metadata[:command]
    assert_equal "https://hooks.slack.com/commands/T12345678/12345/abc123", command.metadata[:response_url]
  end

  test "parse handles empty text" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert_equal "", command.text
    assert command.blank?
  end

  test "parse strips whitespace from text" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "  help me  ",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert_equal "help me", command.text
  end

  test "parse handles nil text" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => nil,
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert_equal "", command.text
    assert command.blank?
  end

  test "parse returns nil workspace_id for non-existent workspace" do
    payload = {
      "team_id" => "TNONEXIST", # Non-existent workspace
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert_nil command.workspace_id
    refute command.valid? # Should be invalid because workspace_id is required
  end

  test "parsed command is valid when workspace exists" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert command.valid?
    assert_empty command.errors
  end

  test "parsed command can access workspace record" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert_equal @workspace, command.workspace
    assert_equal @workspace.name, command.workspace.name
  end

  test "parsed command identifies as slack platform" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "help",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert command.slack?
    refute command.teams?
  end

  test "parsed command can extract subcommand" do
    payload = {
      "team_id" => @workspace.platform_id,
      "user_id" => "U12345678",
      "text" => "status --verbose",
      "trigger_id" => "123456.789.abc123",
      "channel_id" => "C12345678"
    }

    command = Slack::CommandAdapter.parse(payload)

    assert_equal "status", command.subcommand
    assert_equal [ "status", "--verbose" ], command.args
  end
end
