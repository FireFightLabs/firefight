require "test_helper"

class IncidentInviteServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @service = IncidentInviteService.new(@workspace)
  end

  test "invites each user once" do
    Slack::Client.expects(:invite_to_channel).times(2).returns({ ok: true })

    result = @service.invite!(incident: @incident, user_ids: [ "U11111111", "U22222222", "U11111111" ])

    assert_equal [ "U11111111", "U22222222" ], result[:invited_user_ids]
    assert_empty result[:already_in_channel_user_ids]
    assert_empty result[:failed_invites]
  end

  test "treats already_in_channel as non-fatal" do
    Slack::Client.expects(:invite_to_channel).raises(Slack::Client::AlreadyInChannelError.new("already_in_channel"))

    result = @service.invite!(incident: @incident, user_ids: [ "U11111111" ])

    assert_empty result[:invited_user_ids]
    assert_equal [ "U11111111" ], result[:already_in_channel_user_ids]
    assert_empty result[:failed_invites]
  end

  test "treats cant_invite_self as non-fatal" do
    Slack::Client.expects(:invite_to_channel).raises(Slack::Client::AlreadyInChannelError.new("cant_invite_self"))

    result = @service.invite!(incident: @incident, user_ids: [ "U11111111" ])

    assert_empty result[:invited_user_ids]
    assert_equal [ "U11111111" ], result[:already_in_channel_user_ids]
    assert_empty result[:failed_invites]
  end

  test "collects other invite failures" do
    Slack::Client.expects(:invite_to_channel).raises(Slack::Client::ApiError.new("cant_invite"))

    result = @service.invite!(incident: @incident, user_ids: [ "U11111111" ])

    assert_empty result[:invited_user_ids]
    assert_empty result[:already_in_channel_user_ids]
    assert_equal 1, result[:failed_invites].size
    assert_equal "U11111111", result[:failed_invites].first[:user_id]
  end

  test "resolve_invitees extracts slack mention ids" do
    result = @service.resolve_invitees("invite <@U11111111> <@U22222222|alice>")

    assert_equal [ "U11111111", "U22222222" ], result[:user_ids]
    assert_empty result[:unresolved_handles]
    assert result[:had_target_tokens]
  end

  test "resolve_invitees extracts raw user ids" do
    result = @service.resolve_invitees("invite U11111111 U22222222")

    assert_equal [ "U11111111", "U22222222" ], result[:user_ids]
    assert result[:had_target_tokens]
  end

  test "resolve_invitees resolves @handle via local membership" do
    result = @service.resolve_invitees("invite @alice")

    assert_equal [ "U12345678" ], result[:user_ids]
    assert_empty result[:unresolved_handles]
    assert result[:had_target_tokens]
  end

  test "resolve_invitees falls back to adapter for unknown handles" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:resolve_user_ids_from_handles).with(handles: [ "nina" ]).returns({
      resolved_user_ids: [ "U99999999" ],
      unresolved_handles: []
    })

    service = IncidentInviteService.new(@workspace)
    result = service.resolve_invitees("invite @nina")

    assert_equal [ "U99999999" ], result[:user_ids]
    assert_empty result[:unresolved_handles]
  end

  test "resolve_invitees returns unresolved handles when adapter cannot resolve" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:resolve_user_ids_from_handles).with(handles: [ "nina" ]).returns({
      resolved_user_ids: [],
      unresolved_handles: [ "nina" ]
    })

    service = IncidentInviteService.new(@workspace)
    result = service.resolve_invitees("invite @nina")

    assert_empty result[:user_ids]
    assert_equal [ "nina" ], result[:unresolved_handles]
    assert result[:had_target_tokens]
  end

  test "resolve_invitees returns empty result for bare subcommand with no targets" do
    result = @service.resolve_invitees("invite")

    assert_empty result[:user_ids]
    assert_empty result[:unresolved_handles]
    assert_not result[:had_target_tokens]
  end

  test "summary_message with all invited" do
    result = { invited_user_ids: [ "U1", "U2" ], already_in_channel_user_ids: [], failed_invites: [] }

    assert_equal "Invited 2 responders.", @service.summary_message(result)
  end

  test "summary_message with singular invited" do
    result = { invited_user_ids: [ "U1" ], already_in_channel_user_ids: [], failed_invites: [] }

    assert_equal "Invited 1 responder.", @service.summary_message(result)
  end

  test "summary_message with mixed results" do
    result = { invited_user_ids: [ "U1" ], already_in_channel_user_ids: [ "U2" ], failed_invites: [ { user_id: "U3", error: "err" } ] }

    assert_includes @service.summary_message(result), "Invited 1 responder."
    assert_includes @service.summary_message(result), "<@U2> is already in this channel."
    assert_includes @service.summary_message(result), "1 failed."
  end

  test "summary_message with no invites" do
    result = { invited_user_ids: [], already_in_channel_user_ids: [], failed_invites: [] }

    assert_equal "No responders were invited.", @service.summary_message(result)
  end

  test "target_tokens? detects slack mentions, raw ids, and @handles" do
    assert IncidentInviteService.target_tokens?("invite <@U11111111>")
    assert IncidentInviteService.target_tokens?("invite U12345678")
    assert IncidentInviteService.target_tokens?("invite @alice")
    assert_not IncidentInviteService.target_tokens?("invite")
    assert_not IncidentInviteService.target_tokens?("")
    assert_not IncidentInviteService.target_tokens?(nil)
  end

  test "resolve_and_notify! invites users and posts summary ephemeral" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.stubs(:for).with(@workspace).returns(adapter)
    adapter.expects(:invite_user).with(channel_id: @incident.channel_id, user_id: "U11111111").returns({ invited_user: "U11111111" })
    adapter.expects(:post_ephemeral).with(channel_id: "C_FROM", user_id: "U_FROM", text: "Invited 1 responder.").once

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
    adapter.expects(:resolve_user_ids_from_handles).with(handles: [ "nina" ]).returns({
      resolved_user_ids: [],
      unresolved_handles: [ "nina" ]
    })
    adapter.expects(:post_ephemeral).with do |args|
      args[:channel_id] == "C_FROM" && args[:user_id] == "U_FROM" && args[:text].include?("Couldn't resolve") && args[:text].include?("@nina")
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
