require "test_helper"

class WorkspaceOnboardingTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
      platform: "slack", platform_id: "T#{SecureRandom.hex(8)}", name: "Fresh Co",
      access_token: "xoxb-test-token", installed_at: Time.current
    )
    @workspace.setup_incident_configuration!
    @installer = @workspace.workspace_memberships.create!(user: users(:charlie), platform_user_id: "U_INSTALLER", role: "owner", joined_at: Time.current)
    @onboarding = @workspace.create_onboarding!(installer: @installer)
  end

  test "the stage starts at none and follows the first test incident" do
    assert_equal WorkspaceOnboarding::STAGE_NONE, @onboarding.stage

    incident = declare!
    assert_equal WorkspaceOnboarding::STAGE_DECLARED, @onboarding.stage

    incident.lead = @installer
    incident.save!
    assert_equal WorkspaceOnboarding::STAGE_LED, @onboarding.stage

    incident.incident_transcript_messages.create!(workspace: @workspace, message_id: "1.1", platform_user_id: "U_INSTALLER", workspace_membership: @installer, content: "502s", posted_at: Time.current)
    assert_equal WorkspaceOnboarding::STAGE_MESSAGED, @onboarding.stage

    incident.update!(incident_status: @workspace.incident_statuses.closed.first!)
    assert_equal WorkspaceOnboarding::STAGE_RESOLVED, @onboarding.stage

    Postmortem.start_blank!(incident, by: @installer)
    assert_equal WorkspaceOnboarding::STAGE_DONE, @onboarding.stage
  end

  test "a generating placeholder is not a postmortem yet" do
    incident = declare!
    incident.update!(incident_status: @workspace.incident_statuses.closed.first!)
    Postmortem.start_generation!(incident, by: @installer)

    assert_equal WorkspaceOnboarding::STAGE_RESOLVED, @onboarding.stage
  end

  test "a canceled first incident ends the loop" do
    incident = declare!
    incident.update!(incident_status: @workspace.incident_statuses.canceled.first!)

    assert_equal WorkspaceOnboarding::STAGE_DONE, @onboarding.stage
  end

  test "only the first test incident is tracked, never a real one" do
    real = declare!(test: false)
    first = declare!
    second = declare!

    assert_not @onboarding.tracks?(real)
    assert @onboarding.tracks?(first)
    assert_not @onboarding.tracks?(second)
    assert_equal first, @onboarding.first_incident
  end

  test "the dialog is the installer's, once" do
    other = @workspace.workspace_memberships.create!(user: users(:alice), platform_user_id: "U_OTHER", role: "member", joined_at: Time.current)

    assert @onboarding.dialog_pending_for?(@installer)
    assert_not @onboarding.dialog_pending_for?(other)

    @onboarding.dismiss_dialog!
    assert_not @onboarding.reload.dialog_pending_for?(@installer)
  end

  test "the dialog goes away once a test incident exists, however it was declared" do
    assert @onboarding.dialog_pending_for?(@installer)

    declare!

    assert_not @onboarding.dialog_pending_for?(@installer)
  end

  private

  def declare!(test: true)
    @workspace.incidents.create!(
      declared_by: @installer,
      incident_status: @workspace.incident_statuses.default_status,
      incident_severity: @workspace.incident_severities.first!,
      name: "First one", is_private: false, is_test: test, declared_at: Time.current, source: Incident::SOURCE_SLACK
    )
  end
end
