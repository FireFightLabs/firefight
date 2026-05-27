require "test_helper"

class Slack::HandleResolverTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @resolver = Slack::HandleResolver.new(@workspace)
  end

  test "target_tokens? detects slack mentions, raw ids, and @handles" do
    assert Slack::HandleResolver.target_tokens?("invite <@U11111111>")
    assert Slack::HandleResolver.target_tokens?("invite U12345678")
    assert Slack::HandleResolver.target_tokens?("invite @alice")
    assert_not Slack::HandleResolver.target_tokens?("invite")
    assert_not Slack::HandleResolver.target_tokens?("")
    assert_not Slack::HandleResolver.target_tokens?(nil)
  end

  test "extracts slack mention ids" do
    result = @resolver.resolve("invite <@U11111111> <@U22222222|alice>")

    assert_equal [ "U11111111", "U22222222" ], result[:user_ids]
    assert_empty result[:unresolved_handles]
    assert result[:had_target_tokens]
  end

  test "extracts raw user ids" do
    result = @resolver.resolve("invite U11111111 U22222222")

    assert_equal [ "U11111111", "U22222222" ], result[:user_ids]
    assert result[:had_target_tokens]
  end

  test "resolves @handle via local membership" do
    result = @resolver.resolve("invite @alice")

    assert_equal [ "U12345678" ], result[:user_ids]
    assert_empty result[:unresolved_handles]
    assert result[:had_target_tokens]
  end

  test "falls back to adapter for unknown handles" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:resolve_user_ids_from_handles).with(handles: [ "nina" ]).returns({
      resolved_user_ids: [ "U99999999" ],
      unresolved_handles: []
    })

    resolver = Slack::HandleResolver.new(@workspace)
    result = resolver.resolve("invite @nina")

    assert_equal [ "U99999999" ], result[:user_ids]
    assert_empty result[:unresolved_handles]
  end

  test "returns unresolved handles when adapter cannot resolve" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:resolve_user_ids_from_handles).with(handles: [ "nina" ]).returns({
      resolved_user_ids: [],
      unresolved_handles: [ "nina" ]
    })

    resolver = Slack::HandleResolver.new(@workspace)
    result = resolver.resolve("invite @nina")

    assert_empty result[:user_ids]
    assert_equal [ "nina" ], result[:unresolved_handles]
    assert result[:had_target_tokens]
  end

  test "returns empty result for bare subcommand with no targets" do
    result = @resolver.resolve("invite")

    assert_empty result[:user_ids]
    assert_empty result[:unresolved_handles]
    assert_not result[:had_target_tokens]
  end
end
