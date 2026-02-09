require "test_helper"

class Interactions::HomeActionSelectHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "updates modal with help text for selected action" do
    stub_update_modal

    result = Interactions::HomeActionSelectHandler.execute(build_payload("new"))

    assert_nil result
  end

  test "returns nil on API error" do
    stub_update_modal(raises: Slack::Client::ApiError.new("update failed"))

    result = Interactions::HomeActionSelectHandler.execute(build_payload("new"))

    assert_nil result
  end

  private

  def build_payload(selected_value)
    {
      "type" => "block_actions",
      "team" => { "id" => @workspace.platform_id },
      "view" => {
        "id" => "V123",
        "title" => { "type" => "plain_text", "text" => "Incident Home" },
        "close" => { "type" => "plain_text", "text" => "Close" },
        "blocks" => [
          { "type" => "section", "text" => { "type" => "mrkdwn", "text" => "*I want to...*" } },
          { "block_id" => "action_select_block", "type" => "input" },
          { "block_id" => "command_details_block", "type" => "section", "text" => { "type" => "mrkdwn", "text" => "placeholder" } }
        ]
      },
      "actions" => [ {
        "action_id" => Slack::Identifiers::HOME_ACTION_SELECT,
        "selected_option" => { "value" => selected_value }
      } ]
    }
  end
end
