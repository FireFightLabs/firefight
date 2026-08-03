require "test_helper"

class IncidentUpdateModalOpenerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles,
           :incident_forms, :incident_form_fields, :catalog_types, :incident_field_definitions, :incident_field_options

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @user_id = "U12345678"
  end

  test "posts temp message and opens incident update modal" do
    stub_post_message

    Slack::Client.expects(:open_modal).once.returns({ ok: true, view: { id: "V12345678" } })

    IncidentUpdateModalOpener.open(
      workspace: @workspace,
      incident: @incident,
      trigger_id: "12345.trigger",
      user_id: @user_id
    )
  end

  test "cleans up temp message when trigger expires" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))
    stub_delete_message

    assert_raises(AdapterError::TriggerExpired) do
      IncidentUpdateModalOpener.open(
        workspace: @workspace,
        incident: @incident,
        trigger_id: "12345.trigger",
        user_id: @user_id
      )
    end
  end

  test "suppresses delete errors during cleanup" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))
    Slack::Client.stubs(:delete_message).raises(Slack::Client::ApiError.new("delete failed"))

    assert_raises(AdapterError::TriggerExpired) do
      IncidentUpdateModalOpener.open(
        workspace: @workspace,
        incident: @incident,
        trigger_id: "12345.trigger",
        user_id: @user_id
      )
    end
  end
end
