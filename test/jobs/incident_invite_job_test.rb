require "test_helper"

class IncidentInviteJobTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "delegates to IncidentInviteService#resolve_and_notify!" do
    service = mock("incident_invite_service")
    IncidentInviteService.expects(:new).with { |ws| ws.id == @workspace.id }.returns(service)
    service.expects(:resolve_and_notify!).with do |args|
      args[:incident].id == @incident.id &&
        args[:text] == "invite <@U11111111>" &&
        args[:channel_id] == "C_FROM" &&
        args[:user_id] == "U_FROM"
    end

    IncidentInviteJob.perform_now(
      workspace_id: @workspace.id,
      incident_id: @incident.id,
      text: "invite <@U11111111>",
      channel_id: "C_FROM",
      user_id: "U_FROM"
    )
  end
end
