require "test_helper"

class Interactions::ReopenIncidentHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper


  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @resolved_status = incident_statuses(:resolved_ws1)
    @investigating_status = incident_statuses(:investigating_ws1)
    @severity = incident_severities(:critical_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @resolved_status,
      incident_severity: @severity,
      name: "Test incident",
      summary: "Something was broken",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
  end

  test "reopens incident and sets default live status" do
    stub_all_side_effects

    result = Interactions::ReopenIncidentHandler.execute(build_interaction)

    assert_nil result
    @incident.reload
    assert @incident.active?
    assert_equal @investigating_status, @incident.incident_status
  end

  test "clears resolved_at via Lifecycle concern" do
    stub_all_side_effects

    Interactions::ReopenIncidentHandler.execute(build_interaction)

    assert_nil @incident.reload.resolved_at
  end

  test "reopens incident without reason" do
    stub_all_side_effects

    result = Interactions::ReopenIncidentHandler.execute(build_interaction(reason: nil))

    assert_nil result
    @incident.reload
    assert @incident.active?
  end

  test "creates INCIDENT_REOPENED event with incident update" do
    stub_all_side_effects

    assert_difference [ "IncidentEvent.count", "IncidentUpdate.count" ], 1 do
      Interactions::ReopenIncidentHandler.execute(
        build_interaction(reason: "Issue is still occurring")
      )
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_REOPENED)
    assert_equal @member, event.actor
    assert_instance_of IncidentUpdate, event.eventable
    assert_equal IncidentUpdate::REOPENED, event.eventable.update_type
    assert_equal "Issue is still occurring", event.eventable.message
    assert event.changed?(:status)
    assert event.changed?(:resolved_at)
    assert_equal "Issue is still occurring", event.metadata["reason"]
  end

  test "starts IncidentReopenWorkflow with context including reason" do
    stub_all_side_effects

    assert_difference "SolidWorkflow::Workflow.count", 1 do
      Interactions::ReopenIncidentHandler.execute(
        build_interaction(reason: "Not actually fixed")
      )
    end

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.reopen.v1", subject: @incident)
    assert_equal @member.platform_user_id, workflow.context["reopened_by_platform_user_id"]
    assert_equal "Not actually fixed", workflow.context["reason"]
  end

  test "returns error when incident is already active" do
    @incident.update!(incident_status: @investigating_status, resolved_at: nil)
    stub_all_side_effects

    result = Interactions::ReopenIncidentHandler.execute(build_interaction)

    assert_equal "errors", result[:response_action]
    assert_includes result[:errors]["reason_block"], "already active"
  end

  test "returns error when incident not found" do
    stub_delete_message

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::REOPEN_INCIDENT_MODAL,
      private_metadata: { incident_id: SecureRandom.uuid, temp_message_ts: "1234567890.123456", channel_id: "C12345678" }.to_json,
      values: build_values
    )

    result = Interactions::ReopenIncidentHandler.execute(interaction)

    assert_equal "errors", result[:response_action]
  end

  test "cleans up temp message on success" do
    stub_update_message
    stub_post_message
    stub_set_channel_topic
    Slack::Client.expects(:delete_message).once.returns({ ok: true, ts: "1234567890.123456", channel: "C12345678" })

    Interactions::ReopenIncidentHandler.execute(build_interaction)
  end

  private

  def build_interaction(reason: "Issue recurring")
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::REOPEN_INCIDENT_MODAL,
      private_metadata: { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json,
      values: build_values(reason: reason)
    )
  end

  def build_values(reason: "Issue recurring")
    {
      "reason_block" => {
        "reason_input" => { "value" => reason }
      }
    }
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_delete_message
    stub_set_channel_topic
  end
end
