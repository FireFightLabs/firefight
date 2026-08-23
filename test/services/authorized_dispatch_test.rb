require "test_helper"

class AuthorizedDispatchTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  # Every route the two dispatchers can reach has to say what it authorizes as,
  # or a handler could be added that quietly runs ungated.
  test "every dispatchable handler declares an authorization" do
    handlers = InteractionDispatcher::VIEW_SUBMISSION_HANDLERS.values +
               InteractionDispatcher::BLOCK_ACTION_HANDLERS.values +
               InteractionDispatcher::SHORTCUT_HANDLERS.values +
               Commands::HomeHandler::SUBCOMMAND_HANDLERS.values +
               [ Interactions::UnknownHandler, Interactions::ViewClosedHandler,
                 Commands::DeclareIncident, Commands::HomeHandler ]

    handlers.uniq.each do |handler|
      assert_nothing_raised { handler.authorization }
      assert handler.authorization.present?, "#{handler.name} declares no authorization"
    end
  end

  test "a member participates in an incident from Slack" do
    interaction = block_action(Identifiers::MARK_ACTION_DONE, @member.platform_user_id)
    Interactions::MarkActionDoneHandler.expects(:execute).with(interaction).once

    InteractionDispatcher.dispatch(interaction)
  end

  test "a member is refused an action their authority does not cover" do
    interaction = block_action(Identifiers::MARK_ACTION_DONE, @member.platform_user_id)
    WorkspaceMembership.any_instance.stubs(:implicitly_allowed?).returns(false)
    Interactions::MarkActionDoneHandler.expects(:execute).never
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).once

    assert_nil InteractionDispatcher.dispatch(interaction)
  end

  test "Slack participation writes no ledger row" do
    interaction = block_action(Identifiers::MARK_ACTION_DONE, @member.platform_user_id)
    Interactions::MarkActionDoneHandler.stubs(:execute).returns(nil)

    assert_no_difference "Ability::Invocation.count" do
      InteractionDispatcher.dispatch(interaction)
    end
  end

  test "a refusal is still ledgered" do
    interaction = block_action(Identifiers::MARK_ACTION_DONE, @member.platform_user_id)
    WorkspaceMembership.any_instance.stubs(:implicitly_allowed?).returns(false)
    Slack::WorkspaceAdapter.any_instance.stubs(:post_ephemeral)

    assert_difference "Ability::Invocation.count", 1 do
      InteractionDispatcher.dispatch(interaction)
    end
  end

  test "handlers that authorize nothing never resolve a principal" do
    interaction = Interaction.new(
      type: Interaction::VIEW_CLOSED, platform: Platforms::SLACK,
      team_id: @workspace.platform_id, user_id: "U_STRANGER"
    )
    WorkspaceMemberProvisioner.expects(:find_or_provision!).never

    InteractionDispatcher.dispatch(interaction)
  end

  private

  def block_action(action_id, user_id)
    Interaction.new(
      type: Interaction::BLOCK_ACTIONS,
      action_id: action_id,
      platform: Platforms::SLACK,
      team_id: @workspace.platform_id,
      user_id: user_id,
      channel_id: "C12345678",
      action_value: @incident.id
    )
  end
end
