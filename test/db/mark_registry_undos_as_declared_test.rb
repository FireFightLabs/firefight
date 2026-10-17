require "test_helper"
require Rails.root.join("db/migrate/20261017110100_mark_registry_undos_as_declared")

class MarkRegistryUndosAsDeclaredTest < ActiveSupport::TestCase
  test "a change made without asking keeps the registry's undo it was given, and a temporary change's written undo is left for the chat" do
    workspace = workspaces(:slack_workspace_one)
    alice = workspace_memberships(:alice_workspace_one)
    chat = Conversation.start_personal!(workspace: workspace, member: alice).chat_record
    step = { "description" => "Label issue on GitHub", "action_key" => "github.label_issue", "arguments" => { "remove" => [ "bug" ] } }
    made = lambda do |call_id, **attributes|
      Chat::Mitigation.create!(chat: chat, workspace: workspace, asker: alice, tool_call_id: call_id, tool_name: "github_label_issue",
                               action_key: "github.label_issue", arguments: {}, status: Chat::Mitigation::STATUS_MADE, started_at: Time.current,
                               undo_state: Chat::Mitigation::UNDO_READY, undo_steps: [ step ], **attributes)
    end
    unasked = made.call("call_made", unasked_reason: Ability::Invocation::UNASKED_SAFE)
    timed = made.call("call_timed", status: Chat::Mitigation::STATUS_ACTIVE, duration_minutes: 60, expires_at: 1.hour.from_now)

    ActiveRecord::Migration.suppress_messages { MarkRegistryUndosAsDeclared.new.migrate(:up) }

    assert unasked.reload.undone_by_firefight?, "its Undo still runs the registry's call"
    assert_not timed.reload.undone_by_firefight?, "a model wrote this one, so Halon puts it back in the chat"
  end
end
