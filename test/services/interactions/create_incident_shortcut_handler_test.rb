require "test_helper"

class Interactions::CreateIncidentShortcutHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
      platform: "slack",
      platform_id: "T#{SecureRandom.hex(8)}",
      name: "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current,
      incidents_channel_id: "C12345678"
    )
  end

  test "opens incident creation modal" do
    stub_open_modal

    payload = {
      "type" => "shortcut",
      "callback_id" => Slack::Identifiers::CREATE_INCIDENT_SHORTCUT,
      "trigger_id" => "12345.trigger",
      "user" => { "id" => "U12345678" },
      "team" => { "id" => @workspace.platform_id }
    }

    result = Interactions::CreateIncidentShortcutHandler.execute(payload)
    assert_nil result
  end

  test "handles trigger expiration" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))

    payload = {
      "type" => "shortcut",
      "callback_id" => Slack::Identifiers::CREATE_INCIDENT_SHORTCUT,
      "trigger_id" => "expired.trigger",
      "user" => { "id" => "U12345678" },
      "team" => { "id" => @workspace.platform_id }
    }

    result = Interactions::CreateIncidentShortcutHandler.execute(payload)
    assert_equal "errors", result[:response_action]
    assert_includes result[:errors][:base], "expired"
  end

  test "raises error if workspace not found" do
    payload = {
      "type" => "shortcut",
      "callback_id" => Slack::Identifiers::CREATE_INCIDENT_SHORTCUT,
      "trigger_id" => "12345.trigger",
      "user" => { "id" => "U12345678" },
      "team" => { "id" => "T_NONEXISTENT" }
    }

    assert_raises(ActiveRecord::RecordNotFound) do
      Interactions::CreateIncidentShortcutHandler.execute(payload)
    end
  end
end
