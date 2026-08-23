require "test_helper"

class Interactions::IncidentUpdateSelectHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "re-renders the open modal without the timer once a closing status is picked" do
    view = capture_updated_view("resolved")

    assert_not_includes block_ids(view), "field_next_update_block"
  end

  test "re-renders the open modal with the timer while the status stays live" do
    view = capture_updated_view("monitoring")

    assert_includes block_ids(view), "field_next_update_block"
  end

  test "keeps the modal pointed at the same incident" do
    view = capture_updated_view("resolved")

    assert_equal @incident.id, Slack::PrivateMetadata.parse(view[:private_metadata]).incident_id
  end

  test "swallows a Slack failure rather than erroring the interaction" do
    stub_update_modal(raises: AdapterError::NotFound.new("view_not_found"))

    assert_nil Interactions::IncidentUpdateSelectHandler.execute(build_interaction("resolved"))
  end

  private

  def capture_updated_view(slug)
    captured = nil
    Slack::Client.stubs(:update_modal).with do |args|
      captured = args[:view]
      true
    end.returns({ ok: true })

    Interactions::IncidentUpdateSelectHandler.execute(build_interaction(slug))
    captured
  end

  def build_interaction(slug)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: workspace_memberships(:alice_workspace_one).platform_user_id,
      action_id: Identifiers::INCIDENT_UPDATE_STATUS_SELECT,
      callback_id: Identifiers::INCIDENT_UPDATE_MODAL,
      view_id: "V12345678",
      private_metadata: Slack::PrivateMetadata.encode(incident_id: @incident.id),
      values: {
        "field_status_block" => {
          Identifiers::INCIDENT_UPDATE_STATUS_SELECT => { "selected_option" => { "value" => slug } }
        }
      }
    )
  end

  def block_ids(view)
    view[:blocks].map { |block| block[:block_id] }
  end
end
