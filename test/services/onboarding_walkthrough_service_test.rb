require "test_helper"

class OnboardingWalkthroughServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
      platform: "slack", platform_id: "T#{SecureRandom.hex(8)}", name: "Coach Co",
      access_token: "xoxb-test-token", installed_at: Time.current, incidents_channel_id: "C_INCIDENTS"
    )
    @workspace.setup_incident_configuration!
    @installer = @workspace.workspace_memberships.create!(user: users(:charlie), platform_user_id: "U_COACH", role: "owner", joined_at: Time.current)
    @onboarding = @workspace.create_onboarding!(installer: @installer)
    @incident = @workspace.incidents.create!(
      declared_by: @installer, incident_status: @workspace.incident_statuses.default_status,
      incident_severity: @workspace.incident_severities.first!, name: "Test run", is_private: false, is_test: true,
      channel_id: "C_TEST_RUN", declared_at: Time.current, source: Incident::SOURCE_SLACK
    )
    @service = OnboardingWalkthroughService.new(@workspace)
  end

  test "posts each step once as the incident earns it and never a step already passed" do
    expect_step(1)
    assert_equal 1, @service.advance!(@incident)[:step]
    assert_equal({ skipped: true }, @service.advance!(@incident))

    @incident.lead = @installer
    @incident.save!
    expect_step(2)
    assert_equal 2, @service.advance!(@incident)[:step]

    @incident.incident_transcript_messages.create!(workspace: @workspace, message_id: "1.1", platform_user_id: "U_COACH", workspace_membership: @installer, content: "502s", posted_at: Time.current)
    expect_step(3)
    assert_equal 3, @service.advance!(@incident)[:step]

    @incident.update!(incident_status: @workspace.incident_statuses.closed.first!)
    expect_step(4)
    assert_equal 4, @service.advance!(@incident)[:step]

    Postmortem.start_blank!(@incident, by: @installer)
    expect_step(5)
    assert_equal 5, @service.advance!(@incident.reload)[:step]
    assert_equal 5, @onboarding.reload.walkthrough_step
  end

  test "a responder who skips ahead gets only the step that matters now" do
    @incident.lead = @installer
    @incident.save!
    @incident.incident_transcript_messages.create!(workspace: @workspace, message_id: "1.2", platform_user_id: "U_COACH", workspace_membership: @installer, content: "502s", posted_at: Time.current)

    expect_step(3)
    assert_equal 3, @service.advance!(@incident)[:step]
  end

  test "a real incident and a second test incident get nothing" do
    real = @incident.dup.tap { |i| i.assign_attributes(is_test: false, sequence_number: nil, identifier: nil, channel_id: "C_REAL"); i.save! }
    second = @incident.dup.tap { |i| i.assign_attributes(sequence_number: nil, identifier: nil, channel_id: "C_SECOND"); i.save! }
    Slack::WorkspaceAdapter.any_instance.expects(:post_first_incident_walkthrough).never

    assert_equal({ skipped: true }, @service.advance!(real))
    assert_equal({ skipped: true }, @service.advance!(second))
  end

  test "two callers arriving together post the step once" do
    WorkspaceOnboarding.where(id: @onboarding.id).update_all(walkthrough_step: 1)
    WorkspaceOnboarding.any_instance.stubs(:walkthrough_step).returns(nil)
    Slack::WorkspaceAdapter.any_instance.expects(:post_first_incident_walkthrough).never

    assert_equal({ skipped: true }, @service.advance!(@incident))
    assert_equal 1, WorkspaceOnboarding.find(@onboarding.id).read_attribute_before_type_cast(:walkthrough_step)
  end

  test "a channel that refuses the post is logged and the step is not marked done" do
    Slack::WorkspaceAdapter.any_instance.stubs(:post_first_incident_walkthrough).raises(AdapterError::NotFound.new("channel_not_found"))

    assert_equal({ skipped: true }, @service.advance!(@incident))
    assert_nil @onboarding.reload.walkthrough_step
  end

  private

  def expect_step(step)
    Slack::WorkspaceAdapter.any_instance.expects(:post_first_incident_walkthrough)
      .with(channel_id: "C_TEST_RUN", incident: @incident, step: step).once.returns({ message_id: "#{step}.0", channel_id: "C_TEST_RUN" })
  end
end
