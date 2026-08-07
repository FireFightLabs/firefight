require "test_helper"

class Interactions::OpenModalRefreshTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_statuses,
           :incident_severities, :incident_lifecycle_stages, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a click from the channel refreshes nothing" do
    Slack::Client.expects(:update_modal).never

    Interactions::OpenModalRefresh.call(interaction(view: nil), @workspace)
  end

  test "a click inside the actions modal redraws it" do
    @incident.incident_actions.create!(
      created_by: @member, description: "Restart the worker",
      action_type: IncidentAction::ACTION_TYPE_ACTION, status: IncidentAction::STATUS_OPEN
    )
    captured = nil
    Slack::Client.expects(:update_modal).with { |args| captured = args }.returns({ ok: true })

    Interactions::OpenModalRefresh.call(interaction(view: view(Identifiers::INCIDENT_ACTIONS_MODAL)), @workspace)

    assert_equal "V1", captured[:view_id]
    assert_match "Restart the worker", captured[:view][:blocks].to_s
  end

  test "an unrecognised modal is left alone rather than guessed at" do
    Slack::Client.expects(:update_modal).never

    Interactions::OpenModalRefresh.call(interaction(view: view(Identifiers::SET_LEAD_MODAL)), @workspace)
  end

  test "a modal whose subject has gone is handled quietly" do
    stale = view(Identifiers::INCIDENT_ACTIONS_MODAL)
    stale["private_metadata"] = Slack::PrivateMetadata.encode(incident_id: SecureRandom.uuid)
    Slack::Client.expects(:update_modal).never

    assert_nil Interactions::OpenModalRefresh.call(interaction(view: stale), @workspace)
  end

  private

  def view(callback_id)
    {
      "id" => "V1",
      "callback_id" => callback_id,
      "private_metadata" => Slack::PrivateMetadata.encode(incident_id: @incident.id)
    }
  end

  def interaction(view:)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      view: view
    )
  end
end
