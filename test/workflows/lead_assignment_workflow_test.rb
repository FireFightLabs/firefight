require "test_helper"

class LeadAssignmentWorkflowTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      summary: "Test summary",
      is_private: false,
      channel_id: "C_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      source: Incident::SOURCE_SLACK
    )

    @incident.lead = @bob
  end

  test "full workflow succeeds" do
    stub_all_side_effects

    workflow = LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })

    assert_equal "succeeded", workflow.state
    assert_equal 6, workflow.steps.count
    assert workflow.steps.all?(&:succeeded?)
  end

  test "updates channel topic with lead name" do
    stub_all_side_effects

    Slack::Client.expects(:set_channel_topic).with(
      has_entries(topic: includes("Lead: #{@bob.user.name}"))
    ).returns({ ok: true, topic: "test" })

    LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })
  end

  test "posts lead expectations as ephemeral" do
    stub_all_side_effects

    Slack::Client.expects(:post_ephemeral).with(
      has_entries(
        user: @bob.platform_user_id,
        text: includes("Incident Lead")
      )
    ).returns({ ok: true, ts: "123.456" })

    LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })
  end

  test "posts lead announcement to channel" do
    stub_all_side_effects

    Slack::Client.expects(:post_message).with(
      has_entries(
        channel: @incident.channel_id,
        text: includes(@bob.platform_user_id)
      )
    ).at_least_once.returns({ ok: true, ts: "123.456" })

    LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })
  end

  test "invites a lead who is not in the channel before showing the expectations" do
    stub_all_side_effects
    invited = sequence("lead invite")

    Slack::Client.expects(:invite_to_channel).with(
      has_entries(channel: @incident.channel_id, users: @bob.platform_user_id)
    ).in_sequence(invited).returns({ ok: true })
    Slack::Client.expects(:post_ephemeral).with(has_entries(user: @bob.platform_user_id)).in_sequence(invited).returns({ ok: true })

    workflow = LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })

    assert_equal "succeeded", workflow.state
    assert_equal 1, workflow.steps.find_by!(name: "invite_lead").output["invited"]
  end

  test "a lead already in the channel changes nothing and raises no error" do
    stub_all_side_effects
    Slack::Client.expects(:invite_to_channel).raises(AdapterError::AlreadyInChannel.new("already_in_channel"))
    Slack::Client.expects(:post_message).with(has_entries(text: includes("Couldn't add"))).never

    workflow = LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })

    assert_equal "succeeded", workflow.state
    assert_equal 1, workflow.steps.find_by!(name: "invite_lead").output["already_in_channel"]
    assert workflow.steps.all?(&:succeeded?)
  end

  test "a failed invite posts a note, skips the expectations and the rest of the workflow carries on" do
    stub_all_side_effects
    Slack::Client.expects(:invite_to_channel).raises(AdapterError.new("users_not_found"))
    Slack::Client.expects(:post_message).with(
      has_entries(channel: @incident.channel_id, text: includes("Couldn't add <@#{@bob.platform_user_id}>"))
    ).once.returns({ ok: true, ts: "123.456" })
    Slack::Client.expects(:post_ephemeral).never

    workflow = LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })

    assert_equal "succeeded", workflow.state
    assert_equal 1, workflow.steps.find_by!(name: "invite_lead").output["failed"]
    assert_equal({ "skipped" => true }, workflow.steps.find_by!(name: "post_lead_expectations").output)
    assert workflow.steps.find_by!(name: "post_lead_expectations").succeeded?
    assert workflow.steps.find_by!(name: "post_lead_announcement").succeeded?
  end

  test "a raised invite is tolerated, the expectations are skipped and the announcement still posts" do
    stub_all_side_effects
    IncidentInviteService.any_instance.stubs(:invite!).raises(ArgumentError.new("boom"))
    Slack::Client.expects(:post_ephemeral).never
    Slack::Client.expects(:post_message).with(
      has_entries(channel: @incident.channel_id, text: includes(@bob.platform_user_id))
    ).once.returns({ ok: true, ts: "123.456" })

    workflow = LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })

    assert_equal "succeeded", workflow.state
    assert_not workflow.steps.find_by!(name: "invite_lead").succeeded?
    assert workflow.steps.find_by!(name: "invite_lead").failure_tolerated?
    assert_equal({ "skipped" => true }, workflow.steps.find_by!(name: "post_lead_expectations").output)
    assert workflow.steps.find_by!(name: "post_lead_expectations").succeeded?
    assert workflow.steps.find_by!(name: "post_lead_announcement").succeeded?
  end

  test "a refused expectations message does not stop the announcement or fail the run" do
    stub_all_side_effects
    Slack::Client.stubs(:post_ephemeral).raises(AdapterError.new("user_not_in_channel"))

    workflow = LeadAssignmentWorkflow.start_inline!(@incident, context: {
      lead_platform_user_id: @bob.platform_user_id
    })
    expectations = workflow.steps.find_by!(name: "post_lead_expectations")

    assert expectations.pending?
    assert workflow.steps.find_by!(name: "post_lead_announcement").succeeded?

    expectations.update!(attempts: expectations.max_attempts - 1, run_at: nil)
    workflow = LeadAssignmentWorkflow.drain_inline!(workflow)

    assert_equal "succeeded", workflow.state
    assert expectations.reload.failure_tolerated?
    assert workflow.steps.find_by!(name: "post_lead_announcement").succeeded?
  end

  test "a lead with no platform account is not invited" do
    stub_all_side_effects
    Slack::Client.expects(:invite_to_channel).never

    workflow = LeadAssignmentWorkflow.start_inline!(@incident, context: { lead_platform_user_id: nil })

    assert_equal({ "skipped" => true }, workflow.steps.find_by!(name: "invite_lead").output)
  end

  private

  def stub_all_side_effects
    stub_invite_to_channel
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_update_message
    stub_post_message
    stub_post_ephemeral
  end
end
