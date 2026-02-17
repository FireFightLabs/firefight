require "test_helper"

class Interactions::AddNewActionHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT"
    )
  end

  test "pushes create action modal" do
    stub_push_modal

    Slack::Client.expects(:push_modal).once.returns({ ok: true, view: { id: "V12345678" } })

    result = Interactions::AddNewActionHandler.execute(build_interaction)

    assert_nil result
  end

  test "handles missing incident silently" do
    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::ADD_NEW_ACTION,
      action_value: SecureRandom.uuid,
      trigger_id: "12345.trigger"
    )

    result = Interactions::AddNewActionHandler.execute(interaction)

    assert_nil result
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      action_id: Identifiers::ADD_NEW_ACTION,
      action_value: @incident.id,
      trigger_id: "12345.trigger"
    )
  end
end
