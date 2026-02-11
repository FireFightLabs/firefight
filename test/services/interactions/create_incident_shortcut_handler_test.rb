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

    result = Interactions::CreateIncidentShortcutHandler.execute(build_interaction)
    assert_nil result
  end

  test "handles trigger expiration" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))

    result = Interactions::CreateIncidentShortcutHandler.execute(build_interaction)
    assert_equal "errors", result[:response_action]
    assert_includes result[:errors][:base], "expired"
  end

  test "raises error if workspace not found" do
    assert_raises(ActiveRecord::RecordNotFound) do
      Interactions::CreateIncidentShortcutHandler.execute(
        build_interaction(team_id: "T_NONEXISTENT")
      )
    end
  end

  private

  def build_interaction(team_id: @workspace.platform_id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: "shortcut",
      team_id: team_id,
      user_id: "U12345678",
      trigger_id: "12345.trigger",
      callback_id: Identifiers::CREATE_INCIDENT_SHORTCUT
    )
  end
end
