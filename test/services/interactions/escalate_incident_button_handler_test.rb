require "test_helper"

class Interactions::EscalateIncidentButtonHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "opens escalate modal" do
    stub_post_message
    stub_open_modal

    result = Interactions::EscalateIncidentButtonHandler.execute(build_interaction)

    assert_nil result
  end

  test "handles trigger expiration gracefully" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))
    stub_delete_message

    result = Interactions::EscalateIncidentButtonHandler.execute(build_interaction)

    assert_nil result
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      trigger_id: "12345.trigger",
      action_id: Identifiers::ESCALATE_INCIDENT,
      action_value: @incident.id,
      channel_id: @incident.channel_id
    )
  end
end
