require "test_helper"

class Interactions::UpdateSummaryHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_statuses, :incident_severities, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "updates incident summary and closes modal" do
    stub_all_side_effects

    result = Interactions::UpdateSummaryHandler.execute(
      build_interaction(summary: "New summary text")
    )

    assert_nil result
    assert_equal "New summary text", @incident.reload.summary
  end

  test "creates incident event" do
    stub_all_side_effects

    assert_difference -> { @incident.incident_events.count }, 1 do
      Interactions::UpdateSummaryHandler.execute(
        build_interaction(summary: "Updated summary")
      )
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_UPDATED)
    assert_equal @member, event.user
    assert event.changed?(:summary)
  end

  test "starts summary update workflow" do
    stub_all_side_effects

    assert_difference "Workflow.count", 1 do
      Interactions::UpdateSummaryHandler.execute(
        build_interaction(summary: "Updated summary")
      )
    end

    workflow = Workflow.find_by!(name: "incident.summary_update.v1", subject: @incident)
    assert_equal @member.platform_user_id, workflow.context["updated_by_platform_user_id"]
  end

  private

  def build_interaction(summary: "New summary")
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::UPDATE_SUMMARY_MODAL,
      private_metadata: @incident.id,
      values: {
        "summary_block" => {
          "summary_input" => {
            "value" => summary
          }
        }
      }
    )
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
  end
end
