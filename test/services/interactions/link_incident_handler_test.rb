require "test_helper"

class Interactions::LinkIncidentHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper


  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @source = incidents(:active_critical_ws1)
    @target = incidents(:active_major_ws1)
  end

  test "creates related link between incidents" do
    stub_all_side_effects

    assert_difference "IncidentRelationship.count", 1 do
      Interactions::LinkIncidentHandler.execute(
        build_interaction(relationship_type: IncidentRelationship::RELATED)
      )
    end

    rel = IncidentRelationship.find_by!(
      incident: @source,
      related_incident: @target,
      relationship_type: IncidentRelationship::RELATED
    )
    assert_equal IncidentRelationship::RELATED, rel.relationship_type
  end

  test "creates related events on both incidents" do
    stub_all_side_effects

    Interactions::LinkIncidentHandler.execute(
      build_interaction(relationship_type: IncidentRelationship::RELATED)
    )

    assert @source.incident_events.find_by(event_type: IncidentEvent::RELATIONSHIP_CREATED)
    assert @target.incident_events.find_by(event_type: IncidentEvent::RELATIONSHIP_CREATED)
  end

  test "marks source as duplicate and cancels it" do
    stub_all_side_effects

    Interactions::LinkIncidentHandler.execute(
      build_interaction(relationship_type: IncidentRelationship::DUPLICATE)
    )

    @source.reload
    assert @source.canceled?
    assert_equal @target, @source.duplicate_of
  end

  test "starts link workflow" do
    stub_all_side_effects

    assert_difference "SolidWorkflow::Workflow.count", 1 do
      Interactions::LinkIncidentHandler.execute(
        build_interaction(relationship_type: IncidentRelationship::RELATED)
      )
    end

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.link.v1", subject: @source)
    assert_equal @member.platform_user_id, workflow.context["linked_by_platform_user_id"]
    assert_equal @target.id, workflow.context["target_incident_id"]
  end

  test "returns nil on success" do
    stub_all_side_effects

    result = Interactions::LinkIncidentHandler.execute(
      build_interaction(relationship_type: IncidentRelationship::RELATED)
    )

    assert_nil result
  end

  test "returns error when target not found" do
    result = Interactions::LinkIncidentHandler.execute(
      build_interaction(target_id: SecureRandom.uuid)
    )

    assert_equal "errors", result[:response_action]
  end

  private

  def build_interaction(relationship_type: IncidentRelationship::RELATED, target_id: nil)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::LINK_INCIDENT_MODAL,
      private_metadata: @source.id,
      values: {
        "relationship_type_block" => {
          "relationship_type_select" => {
            "selected_option" => { "value" => relationship_type }
          }
        },
        "target_incident_block" => {
          "target_incident_select" => {
            "selected_option" => { "value" => target_id || @target.id }
          }
        }
      }
    )
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_set_channel_topic
    stub_set_channel_purpose
  end
end
