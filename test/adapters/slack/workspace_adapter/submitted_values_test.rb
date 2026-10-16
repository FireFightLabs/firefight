require "test_helper"

class Slack::WorkspaceAdapter::SubmittedValuesTest < ActiveSupport::TestCase
  Input = PlatformAdapter::Input

  setup do
    @adapter = Slack::WorkspaceAdapter.new(workspaces(:slack_workspace_one))
    @values = {
      Identifiers::REASON_BLOCK => { Identifiers::REASON_INPUT => { "type" => "plain_text_input", "value" => "Rolled back" } },
      Identifiers::RUNBOOK_BLOCK => { Identifiers::RUNBOOK_SELECT => { "type" => "static_select", "selected_option" => { "value" => "db-failover" } } },
      Identifiers::LEAD_BLOCK => { Identifiers::LEAD_SELECT => { "type" => "users_select", "selected_user" => "U1" } },
      Identifiers::INVITE_USERS_BLOCK => { Identifiers::INVITE_USERS_SELECT => { "type" => "multi_users_select", "selected_users" => [ "U1", "U2" ] } },
      Identifiers::SHARE_TARGET_BLOCK => { Identifiers::SHARE_TARGET_SELECT => { "type" => "multi_conversations_select", "selected_conversations" => [ "C1" ] } },
      Identifiers::TARGET_INCIDENT_BLOCK => { Identifiers::TARGET_INCIDENT_SELECT => { "type" => "static_select", "selected_option" => nil } }
    }
  end

  def read(block_id, input_id, kind) = @adapter.submitted_value(values: @values, block_id: block_id, input_id: input_id, kind: kind)

  test "each kind of input reads its answer from where Slack keeps it" do
    assert_equal "Rolled back", read(Identifiers::REASON_BLOCK, Identifiers::REASON_INPUT, Input::TEXT)
    assert_equal "db-failover", read(Identifiers::RUNBOOK_BLOCK, Identifiers::RUNBOOK_SELECT, Input::OPTION)
    assert_equal "U1", read(Identifiers::LEAD_BLOCK, Identifiers::LEAD_SELECT, Input::USER)
    assert_equal [ "U1", "U2" ], read(Identifiers::INVITE_USERS_BLOCK, Identifiers::INVITE_USERS_SELECT, Input::USERS)
    assert_equal [ "C1" ], read(Identifiers::SHARE_TARGET_BLOCK, Identifiers::SHARE_TARGET_SELECT, Input::CONVERSATIONS)
  end

  test "an input left empty or missing reads as nothing" do
    assert_nil read(Identifiers::TARGET_INCIDENT_BLOCK, Identifiers::TARGET_INCIDENT_SELECT, Input::OPTION)
    assert_nil read(Identifiers::SUMMARY_BLOCK, Identifiers::SUMMARY_INPUT, Input::TEXT)
  end
end
