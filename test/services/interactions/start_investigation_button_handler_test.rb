require "test_helper"

class Interactions::StartInvestigationButtonHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    stub_post_message
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
  end

  test "the button starts a run and says where it came from" do
    assert_enqueued_with(job: InvestigationJob) do
      assert_nil Interactions::StartInvestigationButtonHandler.execute(build_interaction)
    end

    assert_equal Investigation::TRIGGER_BUTTON, @incident.investigations.sole.trigger_source
  end

  test "a button on a finished incident says the incident is over" do
    resolved = incidents(:resolved_minor_ws1)
    Interactions::TerminalNotice.expects(:post).with(
      @workspace, resolved, @member.platform_user_id, regexp_matches(/nothing left to investigate/)
    ).once

    Interactions::StartInvestigationButtonHandler.execute(build_interaction(incident: resolved))

    assert_empty resolved.investigations
  end

  test "a workspace without the flag is told, not ignored" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(
      channel_id: @incident.channel_id, user_id: @member.platform_user_id,
      text: regexp_matches(/not turned on/)
    ).once

    Interactions::StartInvestigationButtonHandler.execute(build_interaction)

    assert_empty @incident.investigations
  end

  test "a second click is told about the run already going" do
    Interactions::StartInvestigationButtonHandler.execute(build_interaction)
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with(
      channel_id: @incident.channel_id, user_id: @member.platform_user_id,
      text: regexp_matches(/Already investigating/)
    ).once

    Interactions::StartInvestigationButtonHandler.execute(build_interaction)

    assert_equal 1, @incident.investigations.count
  end

  test "a deleted incident behind an old button is logged, not raised" do
    interaction = build_interaction
    interaction.stubs(:action_value).returns(SecureRandom.uuid)

    assert_nothing_raised { Interactions::StartInvestigationButtonHandler.execute(interaction) }
  end

  test "declares investigations.create as its authorization" do
    assert_equal [ Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE ],
                 Interactions::StartInvestigationButtonHandler.authorization
  end

  private

  def build_interaction(incident: nil)
    incident ||= @incident
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
      user_id: @member.platform_user_id, trigger_id: "12345.trigger",
      action_id: Identifiers::START_INVESTIGATION, action_value: incident.id,
      channel_id: incident.channel_id
    )
  end
end
