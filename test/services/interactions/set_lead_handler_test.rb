require "test_helper"

class Interactions::SetLeadHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  test "assigns lead and closes modal" do
    stub_all_side_effects

    result = Interactions::SetLeadHandler.execute(
      build_interaction(selected_user_id: @bob.platform_user_id)
    )

    assert_nil result
    assert_equal @bob, @incident.reload.lead
  end

  test "creates lead assigned event with incident update" do
    stub_all_side_effects

    assert_difference [ "IncidentEvent.count", "IncidentUpdate.count" ], 1 do
      Interactions::SetLeadHandler.execute(
        build_interaction(selected_user_id: @bob.platform_user_id)
      )
    end

    event = @incident.incident_events.updates.find_by!(event_type: IncidentEvent::LEAD_ASSIGNED)
    assert_equal @alice, event.actor
    assert_instance_of IncidentUpdate, event.eventable
    assert_equal IncidentUpdate::LEAD_ASSIGNED, event.eventable.update_type
  end

  test "starts lead assignment workflow" do
    stub_all_side_effects

    assert_difference "SolidWorkflow::Workflow.count", 1 do
      Interactions::SetLeadHandler.execute(
        build_interaction(selected_user_id: @bob.platform_user_id)
      )
    end

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.lead_assignment.v1", subject: @incident)
    assert_equal @bob.platform_user_id, workflow.context["lead_platform_user_id"]
  end

  test "refuses to assign a lead on a canceled incident" do
    @incident.update!(incident_status: incident_statuses(:canceled_ws1))

    assert_no_difference "IncidentEvent.count" do
      result = Interactions::SetLeadHandler.execute(
        build_interaction(selected_user_id: @bob.platform_user_id)
      )

      assert_equal "errors", result[:response_action]
      assert_equal "#{@incident.identifier} is canceled, so it can no longer be assigned a lead.",
                   result[:errors]["lead_block"]
    end

    assert_nil @incident.reload.lead
  end

  private

  def build_interaction(selected_user_id:)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @alice.platform_user_id,
      callback_id: Identifiers::SET_LEAD_MODAL,
      private_metadata: @incident.id,
      values: {
        "lead_block" => {
          "lead_select" => {
            "selected_user" => selected_user_id
          }
        }
      }
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
