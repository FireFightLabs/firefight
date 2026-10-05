require "test_helper"

class Interactions::ActionItemEditHandlersTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @action = @incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Restart",
                                                 assignee: @alice, status: IncidentAction::STATUS_IN_PROGRESS, message_ts: "1700000000.000300")
    stub_update_message
    stub_post_message
    stub_get_permalink
  end

  def click(action_id, view_id: nil)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @alice.platform_user_id,
                    channel_id: @incident.channel_id, action_id: action_id, action_value: @action.id, trigger_id: "1.trigger", view_id: view_id)
  end

  def submit(title)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, team_id: @workspace.platform_id, user_id: @alice.platform_user_id,
                    callback_id: Identifiers::RENAME_ACTION_MODAL,
                    private_metadata: ModalState.encode(incident_id: @incident.id, action_item_id: @action.id),
                    values: { Slack::Modals::RenameAction::BLOCK => { Slack::Modals::RenameAction::INPUT => { "value" => title } } })
  end

  test "Rename opens the form holding the title, on top of the item list when it came from there" do
    Slack::WorkspaceAdapter.any_instance.expects(:open_modal).with { |view:, **| view[:callback_id] == Identifiers::RENAME_ACTION_MODAL }
    Interactions::OpenRenameActionHandler.execute(click(Identifiers::RENAME_ACTION))

    Slack::WorkspaceAdapter.any_instance.expects(:push_modal)
    Interactions::OpenRenameActionHandler.execute(click(Identifiers::RENAME_ACTION, view_id: "V1"))
  end

  test "the form renames the item, and keeps itself open with why when it cannot" do
    assert_nil Interactions::RenameActionItemHandler.execute(submit("Restart every worker"))
    assert_equal "Restart every worker", @action.reload.description

    response = Interactions::RenameActionItemHandler.execute(submit(""))
    assert_equal({ Slack::Modals::RenameAction::BLOCK => "Give the item a title." }, response[:errors])
  end

  test "Unassign and Reopen change the item, and a refusal is said to whoever clicked" do
    Interactions::EditActionItemHandler.execute(click(Identifiers::UNASSIGN_ACTION))
    assert_nil @action.reload.assignee

    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(has_entries(text: "That item is not done."))
    Interactions::EditActionItemHandler.execute(click(Identifiers::REOPEN_ACTION))

    @action.update!(status: IncidentAction::STATUS_DONE)
    Interactions::EditActionItemHandler.execute(click(Identifiers::REOPEN_ACTION))
    assert_equal IncidentAction::STATUS_OPEN, @action.reload.status
  end

  test "each is routed and authorized as an incident update" do
    [ Identifiers::RENAME_ACTION, Identifiers::REOPEN_ACTION, Identifiers::UNASSIGN_ACTION ].each do |id|
      assert InteractionDispatcher::BLOCK_ACTION_HANDLERS.key?(id), id
    end
    assert_equal Interactions::RenameActionItemHandler, InteractionDispatcher::VIEW_SUBMISSION_HANDLERS[Identifiers::RENAME_ACTION_MODAL]
  end
end
