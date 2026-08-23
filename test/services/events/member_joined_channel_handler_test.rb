require "test_helper"

class Events::MemberJoinedChannelHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)
  end

  test "provisions member when joining incidents channel" do
    stub_get_user_info

    assert_difference "WorkspaceMembership.count", 1 do
      Events::MemberJoinedChannelHandler.execute(
        Platforms::SLACK,
        build_payload(channel: "C_INCIDENTS", user: "U_NEW_USER")
      )
    end

    membership = @workspace.workspace_memberships.find_by!(platform_user_id: "U_NEW_USER")
    assert_equal "member", membership.role
  end

  test "provisions member when joining active incident channel" do
    incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_INCIDENT_CHANNEL",
      source: Incident::SOURCE_SLACK
    )

    stub_get_user_info

    assert_difference "WorkspaceMembership.count", 1 do
      Events::MemberJoinedChannelHandler.execute(
        Platforms::SLACK,
        build_payload(channel: "C_INCIDENT_CHANNEL", user: "U_NEW_USER")
      )
    end

    membership = @workspace.workspace_memberships.find_by!(platform_user_id: "U_NEW_USER")
    assert_equal "member", membership.role
  end

  test "skips non-incident channels" do
    stub_get_user_info

    assert_no_difference "WorkspaceMembership.count" do
      Events::MemberJoinedChannelHandler.execute(
        Platforms::SLACK,
        build_payload(channel: "C_RANDOM_CHANNEL", user: "U_NEW_USER")
      )
    end
  end

  test "is idempotent for existing members" do
    assert_no_difference "WorkspaceMembership.count" do
      Events::MemberJoinedChannelHandler.execute(
        Platforms::SLACK,
        build_payload(channel: "C_INCIDENTS", user: @member.platform_user_id)
      )
    end
  end

  test "skips when workspace not found" do
    assert_no_difference "WorkspaceMembership.count" do
      Events::MemberJoinedChannelHandler.execute(
        Platforms::SLACK,
        build_payload(team_id: "T_NONEXISTENT", channel: "C12345678", user: "U_NEW_USER")
      )
    end
  end

  test "handles API errors gracefully" do
    stub_get_user_info(raises: AdapterError.new("user_not_found"))

    assert_no_difference "WorkspaceMembership.count" do
      assert_nothing_raised do
        Events::MemberJoinedChannelHandler.execute(
          Platforms::SLACK,
          build_payload(channel: "C_INCIDENTS", user: "U_NEW_USER")
        )
      end
    end
  end

  private

  def build_payload(channel:, user:, team_id: @workspace.platform_id)
    {
      "team_id" => team_id,
      "event" => {
        "type" => "member_joined_channel",
        "user" => user,
        "channel" => channel
      }
    }
  end
end
