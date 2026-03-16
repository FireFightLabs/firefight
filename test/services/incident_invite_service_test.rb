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
    Slack::Client.expects(:invite_to_channel).raises(Slack::Client::ApiError.new("already_in_channel"))

    result = @service.invite!(incident: @incident, user_ids: [ "U11111111" ])

    assert_empty result[:invited_user_ids]
    assert_equal [ "U11111111" ], result[:already_in_channel_user_ids]
    assert_empty result[:failed_invites]
  end

  test "treats cant_invite_self as non-fatal" do
    Slack::Client.expects(:invite_to_channel).raises(Slack::Client::ApiError.new("cant_invite_self"))

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
end
