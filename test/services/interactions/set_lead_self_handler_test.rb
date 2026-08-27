require "test_helper"

class Interactions::SetLeadSelfHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "assigns current user as lead" do
    stub_all_side_effects

    result = Interactions::SetLeadSelfHandler.execute(build_interaction)

    assert_nil result
    assert_equal @alice, @incident.reload.lead
  end

  test "creates lead assigned event with incident update" do
    stub_all_side_effects

    assert_difference [ "IncidentEvent.count", "IncidentUpdate.count" ], 1 do
      Interactions::SetLeadSelfHandler.execute(build_interaction)
    end

    event = @incident.incident_events.updates.find_by!(event_type: IncidentEvent::LEAD_ASSIGNED)
    assert_equal @alice, event.actor
    assert_instance_of IncidentUpdate, event.eventable
    assert_equal IncidentUpdate::LEAD_ASSIGNED, event.eventable.update_type
  end

  test "starts lead assignment workflow" do
    stub_all_side_effects

    assert_difference "SolidWorkflow::Workflow.count", 1 do
      Interactions::SetLeadSelfHandler.execute(build_interaction)
    end

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.lead_assignment.v1", subject: @incident)
    assert_equal @alice.platform_user_id, workflow.context["lead_platform_user_id"]
  end

  test "explains itself instead of assigning a lead on a closed incident" do
    @incident.update!(incident_status: incident_statuses(:resolved_ws1))
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(
      channel_id: @incident.channel_id,
      user_id: @alice.platform_user_id,
      text: "#{@incident.identifier} is closed, so it can no longer be assigned a lead."
    ).once

    assert_no_difference "IncidentEvent.count" do
      assert_nil Interactions::SetLeadSelfHandler.execute(build_interaction)
    end

    assert_nil @incident.reload.lead
  end

  private

  def build_interaction
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @alice.platform_user_id,
      action_id: Identifiers::SET_INCIDENT_LEAD_SELF,
      action_value: @incident.id,
      channel_id: @incident.channel_id
    )
  end

  def stub_all_side_effects
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_update_message
    stub_post_message
    stub_post_ephemeral
  end
end
