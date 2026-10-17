require "test_helper"
require "rake"

class MitigationsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("mitigations:move_old_undo_states")
    Rake::Task["mitigations:move_old_undo_states"].reenable
  end

  test "after the deploy, the moves repeat for a change an older process wrote in a state from before" do
    workspace = workspaces(:slack_workspace_one)
    alice = workspace_memberships(:alice_workspace_one)
    chat = Conversation.start_personal!(workspace: workspace, member: alice).chat_record
    mitigation = Chat::Mitigation.create!(chat: chat, workspace: workspace, asker: alice, tool_call_id: "call_1", tool_name: "posthog_feature_flag_disable",
                                          action_key: "posthog.feature_flag_disable", arguments: {}, duration_minutes: 60,
                                          status: Chat::Mitigation::STATUS_ACTIVE, started_at: Time.current, expires_at: 1.hour.from_now)
    mitigation.update_columns(status: Chat::Mitigation::STATUS_DUE_BY_HAND, undo_state: Chat::Mitigation::UNDO_WRITING)

    Rake::Task["mitigations:move_old_undo_states"].invoke

    stored = Chat::Mitigation.where(id: mitigation.id).pick(:status, :undo_state)
    assert_equal [ Chat::Mitigation::STATUS_UNDO_ASKED, Chat::Mitigation::UNDO_IN_CHAT ], stored
  end
end
