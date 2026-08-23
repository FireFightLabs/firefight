require "test_helper"

class Interactions::InviteRespondersHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "returns validation error when no users selected" do
    result = Interactions::InviteRespondersHandler.execute(build_interaction(selected_users: []))

    assert_equal "errors", result[:response_action]
    assert result[:errors][:invite_users_block].present?
  end

  test "invites selected users and clears modal" do
    service = mock("incident_invite_service")
    IncidentInviteService.expects(:new).with(@workspace).returns(service)
    service.expects(:invite!).with(incident: @incident, user_ids: [ "U11111111", "U22222222" ]).returns({
      invited_user_ids: [ "U11111111", "U22222222" ],
      already_in_channel_user_ids: [],
      failed_invites: []
    })
    service.expects(:summary_message).returns("Invited 2 responders.")

    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:post_ephemeral).with do |args|
      args[:channel_id] == @incident.channel_id &&
        args[:user_id] == @member.platform_user_id &&
        args[:text].include?("Invited 2 responders")
    end

    result = Interactions::InviteRespondersHandler.execute(
      build_interaction(selected_users: [ "U11111111", "U22222222" ])
    )

    assert_equal "clear", result[:response_action]
  end

  test "returns errors when incident is missing" do
    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::INVITE_RESPONDERS_MODAL,
      private_metadata: Slack::PrivateMetadata.encode(incident_id: SecureRandom.uuid),
      values: {
        "invite_users_block" => {
          "invite_users_select" => {
            "selected_users" => [ "U11111111" ]
          }
        }
      }
    )

    result = Interactions::InviteRespondersHandler.execute(interaction)

    assert_equal "errors", result[:response_action]
  end

  private

  def build_interaction(selected_users:)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::INVITE_RESPONDERS_MODAL,
      private_metadata: Slack::PrivateMetadata.encode(incident_id: @incident.id),
      values: {
        "invite_users_block" => {
          "invite_users_select" => {
            "selected_users" => selected_users
          }
        }
      }
    )
  end

  # The modal has always encoded its metadata. The handler read it as a bare id
  # and every invite failed. The old test asserted the handler's shape, not the
  # modal's, which is how it shipped.
  test "the handler accepts exactly what the modal sends" do
    view = Slack::Modals::Invite.build(@incident)

    metadata = Slack::PrivateMetadata.parse(view[:private_metadata])

    assert_equal @incident.id, metadata.incident_id
  end
end
