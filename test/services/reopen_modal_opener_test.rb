require "test_helper"

class ReopenModalOpenerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities,
           :incident_forms, :incident_form_fields, :incident_field_definitions

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @resolved_status = incident_statuses(:resolved_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @resolved_status,
      incident_severity: @severity,
      name: "Closed incident",
      is_private: false,
      channel_id: "C_INCIDENT",
      resolved_at: 1.hour.ago,
      source: Incident::SOURCE_SLACK
    )
  end

  test "posts temp message and opens modal" do
    stub_post_message
    Slack::Client.expects(:open_modal).once.returns({ ok: true })

    ReopenModalOpener.open(
      workspace: @workspace,
      incident: @incident,
      trigger_id: "123.trigger",
      user_id: @member.platform_user_id
    )
  end

  test "cleans up temp message on trigger expiration" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError)
    stub_delete_message

    assert_raises(AdapterError::TriggerExpired) do
      ReopenModalOpener.open(
        workspace: @workspace,
        incident: @incident,
        trigger_id: "123.trigger",
        user_id: @member.platform_user_id
      )
    end
  end
end
