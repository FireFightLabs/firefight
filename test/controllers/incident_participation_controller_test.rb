require "test_helper"

# Escalating, inviting and giving a shoutout from the dashboard. Each calls the
# same service Slack calls, so the record cannot tell which surface it was.
class IncidentParticipationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    @member = workspace_memberships(:alice_workspace_one)
    @other = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
    sign_in(@user, @workspace)

    stub_post_message
    stub_post_ephemeral
    stub_invite_to_channel
  end

  test "escalating names the person, records the ask, and schedules the chase" do
    assert_enqueued_with(job: EscalationAcknowledgementReminderJob) do
      post incident_escalate_path(@incident), params: { member_id: @other.id, reason: "Needs a database owner" }
    end

    assert_redirected_to incident_path(@incident)
    assert_match(/#{@other.display_name} was asked/, flash[:notice])
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_ESCALATED)
    assert_equal @member, event.actor
    assert_equal @other.id, event.metadata["escalated_to_member_id"]
    assert_equal "Needs a database owner", event.metadata["reason"]
  end

  test "an incident that is over says why rather than escalating" do
    close_incident

    assert_no_enqueued_jobs only: EscalationAcknowledgementReminderJob do
      post incident_escalate_path(@incident), params: { member_id: @other.id, reason: "Too late" }
    end

    assert_match(/no longer be escalated/, flash[:alert])
    assert_not @incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_ESCALATED)
  end

  # The channel arrives a moment after the incident does, and all three of
  # these post in it.
  test "an incident whose channel is still being created says so" do
    @incident.update_columns(channel_id: nil)

    post incident_escalate_path(@incident), params: { member_id: @other.id, reason: "Too soon" }
    assert_match(/no channel yet/, flash[:alert])

    post incident_invite_path(@incident), params: { member_ids: [ @other.id ] }
    assert_match(/no channel yet/, flash[:alert])

    post incident_shoutout_path(@incident), params: { member_id: @other.id, message: "Nice work" }
    assert_match(/no channel yet/, flash[:alert])
  end

  test "inviting brings people into the channel and says how many went in" do
    post incident_invite_path(@incident), params: { member_ids: [ @other.id ] }

    assert_redirected_to incident_path(@incident)
    assert_match(/Invited 1 of 1/, flash[:notice])
  end

  test "inviting somebody already in the channel says so rather than claiming success" do
    Slack::Client.stubs(:invite_to_channel).raises(AdapterError::AlreadyInChannel.new("already_in_channel"))

    post incident_invite_path(@incident), params: { member_ids: [ @other.id ] }

    assert_match(/already in the channel/, flash[:notice])
  end

  test "a shoutout records who gave it and who got it" do
    post incident_shoutout_path(@incident),
         params: { member_id: @other.id, message: "Found the leak in minutes" }

    assert_redirected_to incident_path(@incident)
    assert_match(/#{@other.display_name}/, flash[:notice])
    shoutout = @incident.shoutouts.find_by!(to_member_id: @other.id)
    assert_equal @member, shoutout.from_member
    assert_equal "Found the leak in minutes", shoutout.message
  end

  test "a shoutout on an incident that is over says why" do
    close_incident

    post incident_shoutout_path(@incident), params: { member_id: @other.id, message: "Nice work" }

    assert_match(/shoutouts can no longer be posted/, flash[:alert])
    assert_empty @incident.shoutouts
  end

  test "somebody from another workspace is not reachable" do
    post incident_shoutout_path(@incident),
         params: { member_id: workspace_memberships(:alice_workspace_two).id, message: "Hello" }

    assert_response :not_found
  end

  test "another workspace's incident is not reachable" do
    post incident_invite_path(incidents(:active_p0_ws2)), params: { member_ids: [ @other.id ] }

    assert_response :not_found
  end

  test "a member without permission cannot escalate" do
    sign_in(users(:bob), @workspace)
    WorkspaceMembership.any_instance.stubs(:implicitly_permits?).returns(false)

    post incident_escalate_path(@incident), params: { member_id: @other.id, reason: "Nope" }

    assert_not @incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_ESCALATED)
  end

  private

  def close_incident
    stub_update_message
    stub_set_channel_topic
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @member
    )
  end
end
