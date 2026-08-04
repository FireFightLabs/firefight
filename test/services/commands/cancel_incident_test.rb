require "test_helper"

class Commands::CancelIncidentTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents,
           :catalog_types, :incident_field_definitions, :incident_field_options

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @canceled = @workspace.incident_statuses.canceled.active.ordered.first
  end

  def command
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: @member.platform_user_id,
      channel_id: @incident.channel_id,
      trigger_id: "trigger-123",
      text: Identifiers::SUBCOMMAND_CANCEL,
      metadata: { command: "/ff" }
    )
  end

  test "cancels outright when the form has no fields" do
    assert_nil Commands::CancelIncident.execute(command)

    @incident.reload
    assert_equal @canceled.id, @incident.incident_status_id
  end

  test "a canceled incident keeps resolved_at nil so it stays out of time to resolve" do
    Commands::CancelIncident.execute(command)

    @incident.reload
    assert_nil @incident.resolved_at
    assert_nil @incident.time_to_resolve
  end

  test "cancelling clears the next update reminder" do
    @incident.update!(next_update_at: 30.minutes.from_now)

    Commands::CancelIncident.execute(command)

    assert_nil @incident.reload.next_update_at
  end

  test "records its own event rather than a generic update" do
    Commands::CancelIncident.execute(command)

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_CANCELED)
    assert_equal IncidentUpdate::CANCELED, event.eventable.update_type
  end

  test "a canceled incident is not eligible for a postmortem" do
    Commands::CancelIncident.execute(command)

    assert_not @workspace.incidents.closed.exists?(id: @incident.id)
  end

  test "a canceled incident is no longer reachable by the command" do
    Commands::CancelIncident.execute(command)
    result = Commands::CancelIncident.execute(command)

    # Command#incident only finds incidents in a live status, so a second
    # cancel cannot record a second event.
    assert_match "must be run from an incident channel", result[:text]
    assert_equal 1, @incident.incident_events.where(event_type: IncidentEvent::INCIDENT_CANCELED).count
  end

  test "opens a modal instead when the workspace has attached a field" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_CANCEL)
    IncidentFormService.new(@workspace).add_custom_field(form, incident_field_definitions(:customer_tier_ws1))

    CancelModalOpener.expects(:open).once
    assert_nil Commands::CancelIncident.execute(command)

    assert_not_equal @canceled.id, @incident.reload.incident_status_id
  end
end
