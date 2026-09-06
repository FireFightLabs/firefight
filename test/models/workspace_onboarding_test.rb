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

  test "progress starts empty and follows the first incident" do
    assert_not @onboarding.progress.declared

    incident = declare!
    progress = @onboarding.progress
    assert progress.declared
    assert_not progress.lead_set
    assert_not progress.resolved
    assert_not progress.complete?

    incident.lead = @installer
    incident.save!
    assert @onboarding.progress.lead_set

    incident.update!(incident_status: @workspace.incident_statuses.closed.first!)
    assert @onboarding.progress.resolved
    assert_not @onboarding.progress.complete?

    Postmortem.start_blank!(incident, by: @installer)
    assert @onboarding.progress.written_up
    assert @onboarding.progress.complete?
  end

  test "a generating placeholder is not a write-up yet" do
    incident = declare!
    incident.update!(incident_status: @workspace.incident_statuses.closed.first!)
    Postmortem.start_generation!(incident, by: @installer)

    assert_not @onboarding.progress.written_up
  end

  test "a canceled first incident drops the write-up and completes" do
    incident = declare!
    incident.lead = @installer
    incident.save!
    incident.update!(incident_status: @workspace.incident_statuses.canceled.first!)

    progress = @onboarding.progress
    assert progress.resolved
    assert progress.write_up_dropped
    assert progress.complete?
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
