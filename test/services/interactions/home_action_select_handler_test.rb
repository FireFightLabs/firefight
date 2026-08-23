require "test_helper"

class Interactions::HomeActionSelectHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "updates modal with help text for selected action" do
    stub_update_modal

    result = Interactions::HomeActionSelectHandler.execute(build_interaction("new"))

    assert_nil result
  end

  test "returns nil on API error" do
    stub_update_modal(raises: AdapterError.new("update failed"))

    result = Interactions::HomeActionSelectHandler.execute(build_interaction("new"))

    assert_nil result
  end

  private

  def build_interaction(selected_value)
    Interaction.new(
      platform: Platforms::SLACK,
      type: "block_actions",
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      action_id: Identifiers::HOME_ACTION_SELECT,
      selected_value: selected_value,
      view: {
        "id" => "V123",
        "title" => { "type" => "plain_text", "text" => "Incident Home" },
        "close" => { "type" => "plain_text", "text" => "Close" },
        "blocks" => [
          { "type" => "section", "text" => { "type" => "mrkdwn", "text" => "*I want to...*" } },
          { "block_id" => "action_select_block", "type" => "input" },
          { "block_id" => "command_details_block", "type" => "section", "text" => { "type" => "mrkdwn", "text" => "placeholder" } }
        ]
      }
    )
  end
end
