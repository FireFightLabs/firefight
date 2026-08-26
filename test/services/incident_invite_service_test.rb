require "test_helper"

class IncidentInviteServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @service = IncidentInviteService.new(@workspace)
  end

  # A caller that knows someone as a member should not have to look up their
  # platform account first.
  test "invites a member through their platform account" do
    member = workspace_memberships(:bob_workspace_one)
    Slack::Client.expects(:invite_to_channel).returns({ ok: true })

    result = @service.invite!(incident: @incident, people: [ member ])

    assert_equal [ member.platform_user_id ], result.invited_user_ids
  end

  test "invites each user once" do
    Slack::Client.expects(:invite_to_channel).times(2).returns({ ok: true })

    result = @service.invite!(incident: @incident, people: [ "U11111111", "U22222222", "U11111111" ])

    assert_equal [ "U11111111", "U22222222" ], result.invited_user_ids
    assert_empty result.already_in_channel_user_ids
    assert_empty result.failed_invites
  end

  test "treats already_in_channel as non-fatal" do
    Slack::Client.expects(:invite_to_channel).raises(AdapterError::AlreadyInChannel.new("already_in_channel"))

    result = @service.invite!(incident: @incident, people: [ "U11111111" ])

    assert_empty result.invited_user_ids
    assert_equal [ "U11111111" ], result.already_in_channel_user_ids
    assert_empty result.failed_invites
  end

  test "treats cant_invite_self as non-fatal" do
    Slack::Client.expects(:invite_to_channel).raises(AdapterError::AlreadyInChannel.new("cant_invite_self"))

    result = @service.invite!(incident: @incident, people: [ "U11111111" ])

    assert_empty result.invited_user_ids
    assert_equal [ "U11111111" ], result.already_in_channel_user_ids
    assert_empty result.failed_invites
  end

  test "collects other invite failures" do
    Slack::Client.expects(:invite_to_channel).raises(AdapterError.new("cant_invite"))

    result = @service.invite!(incident: @incident, people: [ "U11111111" ])

    assert_empty result.invited_user_ids
    assert_empty result.already_in_channel_user_ids
    assert_equal 1, result.failed_invites.size
    assert_equal "U11111111", result.failed_invites.first[:user_id]
  end

  test "resolve_and_notify! invites users and posts summary ephemeral" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.stubs(:for).with(@workspace).returns(adapter)
    adapter.expects(:resolve_people).with("invite <@U11111111>").returns(user_ids: [ "U11111111" ], unresolved_handles: [], had_target_tokens: true)
    adapter.expects(:invite_user).with(channel_id: @incident.channel_id, user_id: "U11111111").returns({ invited_user: "U11111111" })
    adapter.expects(:post_invite_summary).with do |args|
      args[:channel_id] == "C_FROM" && args[:user_id] == "U_FROM" &&
        args[:result].invited_user_ids == [ "U11111111" ]
    end

    service = IncidentInviteService.new(@workspace)
    service.resolve_and_notify!(
      incident: @incident,
      text: "invite <@U11111111>",
      channel_id: "C_FROM",
      user_id: "U_FROM"
    )
  end

  test "resolve_and_notify! posts unresolved-handle warning when nothing resolves" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.stubs(:for).with(@workspace).returns(adapter)
    adapter.expects(:resolve_people).with("invite @nina").returns(user_ids: [], unresolved_handles: [ "nina" ], had_target_tokens: true)
    adapter.expects(:post_invite_unresolved).with do |args|
      args[:channel_id] == "C_FROM" && args[:user_id] == "U_FROM" &&
        args[:targets][:unresolved_handles] == [ "nina" ]
    end

    service = IncidentInviteService.new(@workspace)
    service.resolve_and_notify!(
      incident: @incident,
      text: "invite @nina",
      channel_id: "C_FROM",
      user_id: "U_FROM"
    )
  end
end
