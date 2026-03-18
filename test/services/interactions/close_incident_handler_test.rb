require "test_helper"

class Interactions::CloseIncidentHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @status = incident_statuses(:investigating_ws1)
    @resolved_status = incident_statuses(:resolved_ws1)
    @severity = incident_severities(:critical_ws1)
    @minor_severity = incident_severities(:minor_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      summary: "Something is broken",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222"
    )
  end

  test "closes incident and sets resolved status" do
    stub_all_side_effects

    result = Interactions::CloseIncidentHandler.execute(build_interaction)

    assert_nil result
    @incident.reload
    assert_equal @resolved_status, @incident.incident_status
    assert @incident.closed?
  end

  test "auto-sets resolved_at via Lifecycle concern" do
    stub_all_side_effects

    freeze_time do
      Interactions::CloseIncidentHandler.execute(build_interaction)

      @incident.reload
      assert_equal Time.current.to_i, @incident.resolved_at.to_i
    end
  end

  test "updates summary when provided" do
    stub_all_side_effects

    Interactions::CloseIncidentHandler.execute(
      build_interaction(summary: "Root cause was a misconfigured load balancer")
    )

    assert_equal "Root cause was a misconfigured load balancer", @incident.reload.summary
  end

  test "keeps existing summary when input is blank" do
    stub_all_side_effects

    Interactions::CloseIncidentHandler.execute(build_interaction(summary: nil))

    assert_equal "Something is broken", @incident.reload.summary
  end

  test "updates name when provided" do
    stub_all_side_effects

    Interactions::CloseIncidentHandler.execute(
      build_interaction(name: "Database connection pool exhaustion")
    )

    assert_equal "Database connection pool exhaustion", @incident.reload.name
  end

  test "updates severity" do
    stub_all_side_effects

    Interactions::CloseIncidentHandler.execute(
      build_interaction(severity_slug: "minor")
    )

    assert_equal @minor_severity, @incident.reload.incident_severity
  end

  test "updates lead when provided" do
    stub_all_side_effects

    Interactions::CloseIncidentHandler.execute(
      build_interaction(lead_user_id: @bob.platform_user_id)
    )

    assert_equal @bob, @incident.reload.lead
  end

  test "creates INCIDENT_RESOLVED event with incident update" do
    stub_all_side_effects

    assert_difference [ "IncidentEvent.count", "IncidentUpdate.count" ], 1 do
      Interactions::CloseIncidentHandler.execute(build_interaction)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_RESOLVED)
    assert_equal @member, event.user
    assert_instance_of IncidentUpdate, event.eventable
    assert event.changed?(:status)
    assert event.changed?(:resolved_at)
  end

  test "starts IncidentCloseWorkflow with context" do
    stub_all_side_effects

    assert_difference "SolidWorkflow::Workflow.count", 1 do
      Interactions::CloseIncidentHandler.execute(build_interaction)
    end

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.close.v1", subject: @incident)
    assert_equal @member.platform_user_id, workflow.context["resolved_by_platform_user_id"]
  end

  test "enqueues channel archival job" do
    stub_all_side_effects

    Interactions::CloseIncidentHandler.execute(build_interaction)

    @incident.reload
    assert_enqueued_with(job: ChannelArchivalJob, args: [ @incident.id, @incident.resolved_at.iso8601 ])
  end

  test "skips channel archival when disabled" do
    @workspace.update!(archive_channel_enabled: false)
    stub_all_side_effects

    Interactions::CloseIncidentHandler.execute(build_interaction)

    assert_no_enqueued_jobs(only: ChannelArchivalJob)
  end

  test "returns error when incident already closed" do
    @incident.update!(incident_status: @resolved_status, resolved_at: Time.current)
    stub_all_side_effects

    result = Interactions::CloseIncidentHandler.execute(build_interaction)

    assert_equal "errors", result[:response_action]
    assert_includes result[:errors]["summary_block"], "already closed"
  end

  test "returns error when incident not found" do
    stub_delete_message

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::CLOSE_INCIDENT_MODAL,
      private_metadata: { incident_id: SecureRandom.uuid, temp_message_ts: "1234567890.123456", channel_id: "C12345678" }.to_json,
      values: build_values
    )

    result = Interactions::CloseIncidentHandler.execute(interaction)

    assert_equal "errors", result[:response_action]
  end

  test "cleans up temp message on success" do
    stub_update_message
    stub_post_message
    stub_set_channel_topic
    Slack::Client.expects(:delete_message).once.returns({ ok: true, ts: "1234567890.123456", channel: "C12345678" })

    Interactions::CloseIncidentHandler.execute(build_interaction)
  end

  private

  def build_interaction(name: nil, summary: nil, severity_slug: "critical", lead_user_id: nil)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::CLOSE_INCIDENT_MODAL,
      private_metadata: { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json,
      values: build_values(name: name, summary: summary, severity_slug: severity_slug, lead_user_id: lead_user_id)
    )
  end

  def build_values(name: nil, summary: nil, severity_slug: "critical", lead_user_id: nil)
    {
      "name_block" => {
        "name_input" => { "value" => name }
      },
      "summary_block" => {
        "summary_input" => { "value" => summary }
      },
      "severity_block" => {
        "severity_select" => {
          "selected_option" => { "value" => severity_slug }
        }
      },
      "lead_block" => {
        "lead_select" => { "selected_user" => lead_user_id }
      }
    }
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_delete_message
    stub_set_channel_topic
  end
end
