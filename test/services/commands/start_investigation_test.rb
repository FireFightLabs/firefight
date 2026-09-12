require "test_helper"

class Commands::StartInvestigationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    stub_post_message
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
  end

  test "a responder in an incident channel starts a run" do
    assert_enqueued_with(job: InvestigationJob) do
      assert_nil Commands::StartInvestigation.execute(build_command)
    end

    investigation = @incident.investigations.sole
    assert_equal Investigation::TRIGGER_COMMAND, investigation.trigger_source
    assert_equal @member, investigation.triggered_by
  end

  test "a workspace without the flag is told the feature is not on" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)

    result = nil
    assert_no_enqueued_jobs(only: InvestigationJob) { result = Commands::StartInvestigation.execute(build_command) }

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_match "not turned on", result[:text]
  end

  test "a blocked entitlement stops the run with its own sentence" do
    message = deny_entitlements!

    result = Commands::StartInvestigation.execute(build_command)

    assert_equal message, result[:text]
    assert_empty @incident.investigations
  end

  test "outside an incident channel it says where to run it" do
    result = Commands::StartInvestigation.execute(build_command(channel_id: "C00000000"))

    assert_match "incident channel", result[:text]
  end

  # A command only resolves a live incident, so a finished channel reads as no incident at all.
  test "in a channel whose incident is over it says where to run it" do
    resolved = incidents(:resolved_minor_ws1)

    result = Commands::StartInvestigation.execute(build_command(channel_id: resolved.channel_id))

    assert_match "incident channel", result[:text]
    assert_empty resolved.investigations
  end

  test "a second ask is told about the run already going" do
    Commands::StartInvestigation.execute(build_command)

    result = nil
    assert_no_enqueued_jobs(only: InvestigationJob) { result = Commands::StartInvestigation.execute(build_command) }

    assert_match "Already investigating", result[:text]
    assert_equal 1, @incident.investigations.count
  end

  test "declares investigations.create as its authorization" do
    assert_equal [ Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE ],
                 Commands::StartInvestigation.authorization
  end

  private

  def build_command(channel_id: nil)
    Command.new(
      platform: Platforms::SLACK, workspace_id: @workspace.id, user_id: @member.platform_user_id,
      text: Identifiers::SUBCOMMAND_INVESTIGATE, trigger_id: "12345.trigger",
      channel_id: channel_id || @incident.channel_id, metadata: { command: "/ff" }
    )
  end
end
