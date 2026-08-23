require "test_helper"

class Commands::CancelIncidentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "announces the cancellation so the channel is not left silent" do
    IncidentCancelWorkflow.expects(:start!).once

    Commands::CancelIncident.execute(command)
  end

  test "a canceled incident offers no quick actions" do
    Commands::CancelIncident.execute(command)

    blocks = Slack::Messages::QuickActions.build(@incident.reload)
    actions = blocks.find { |b| b[:type] == "actions" }
    assert_nil actions, "a canceled incident should offer no actions"
  end

  test "a canceled incident can be reopened, because dismissing it can be wrong" do
    Commands::CancelIncident.execute(command)

    found = @workspace.incidents.terminal.in_channel(@incident.channel_id).first
    assert_equal @incident.id, found&.id
  end

  test "the editor shows status on cancel even when responders will not be asked" do
    editor = IncidentFormResolver.new(@workspace).resolve(IncidentForm::SLUG_CANCEL, include_hidden: true)

    # Configuration has to explain what Slack does. A field that can appear must
    # be visible here, or its appearance later is inexplicable.
    assert_includes editor.map(&:system_field_key), IncidentSystemField::KEY_STATUS
  end

  test "slack skips status while a single canceled status leaves nothing to choose" do
    assert_empty Slack::Modals::IncidentCancel.build(@incident)[:blocks]
  end

  test "slack asks for status once a second canceled status exists" do
    stage = IncidentLifecycleStage.find_by!(key: IncidentLifecycleStage::CANCELED)
    @workspace.incident_statuses.create!(
      name: "Duplicate", slug: "duplicate", incident_lifecycle_stage: stage,
      position: @workspace.incident_statuses.maximum(:position).to_i + 1
    )

    blocks = Slack::Modals::IncidentCancel.build(@incident)[:blocks]
    assert_equal [ "field_status_block" ], blocks.map { |b| b[:block_id] }
  end

  test "an available field is offered in the editor but hidden from responders" do
    resolver = IncidentFormResolver.new(@workspace)

    editor = resolver.resolve(IncidentForm::SLUG_CANCEL, include_hidden: true)
    assert_includes editor.map(&:system_field_key), IncidentSystemField::KEY_SUMMARY,
      "an available field must be reachable, or it can never be turned on"
    assert_empty resolver.resolve(IncidentForm::SLUG_CANCEL)
  end

  test "enabling an available field puts it in front of responders" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_CANCEL)
    service = IncidentFormService.new(@workspace)
    field = service.ensure_system_field!(form, IncidentSystemField::KEY_SUMMARY)

    assert_equal IncidentFormField::VISIBILITY_MODE_HIDDEN, field.visibility_mode
    service.update_field(field, visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL)

    resolved = IncidentFormResolver.new(@workspace).resolve(IncidentForm::SLUG_CANCEL)
    assert_equal [ IncidentSystemField::KEY_SUMMARY ], resolved.map(&:system_field_key)
  end

  test "asking for a postmortem on a canceled incident says why, not that the channel is wrong" do
    Commands::CancelIncident.execute(command)

    result = Commands::GeneratePostmortem.execute(command)

    assert_match "was canceled", result[:text]
    assert_no_match(/incident channel/, result[:text])
  end

  test "the cancellation message names who did it and calls it a cancellation" do
    Commands::CancelIncident.execute(command)

    blocks = Slack::Messages::StatusUpdate.build(
      @incident.reload, message: nil, updated_by_platform_user_id: "U9", scope: :inline
    )
    text = blocks.filter_map { |b| b.dig(:text, :text) || b[:elements]&.map { |e| e[:text] }&.join(" ") }.join(" ")

    assert_match "Incident canceled", text
    assert_match "Canceled by <@U9>", text
    assert_no_match(/Incident updated|Updated by/, text)
  end

  test "a canceled incident can be reopened through the modal, not just found" do
    Commands::CancelIncident.execute(command)

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::REOPEN_INCIDENT_MODAL,
      private_metadata: { incident_id: @incident.id }.to_json,
      values: { "reason_block" => { "reason_input" => { "value" => "It was real after all." } } }
    )

    result = Interactions::ReopenIncidentHandler.execute(interaction)

    assert_nil result, "reopening a canceled incident must not report it as already active"
    assert @incident.reload.incident_status.incident_lifecycle_stage.open?
  end

  test "cancelling schedules the channel archival it promises" do
    @workspace.update!(archive_channel_enabled: true)

    assert_enqueued_with(job: ChannelArchivalJob) do
      Commands::CancelIncident.execute(command)
    end
  end

  test "a summary typed while cancelling is kept and shown to the channel" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_CANCEL)
    service = IncidentFormService.new(@workspace)
    field = service.ensure_system_field!(form, IncidentSystemField::KEY_SUMMARY)
    service.update_field(field, visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL)

    IncidentCancelWorkflow.expects(:start!).with do |_incident, context:|
      context[:message] == "Duplicate of INC-041."
    end

    Interactions::CancelIncidentHandler.execute(Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::CANCEL_INCIDENT_MODAL,
      private_metadata: { incident_id: @incident.id }.to_json,
      values: { "field_summary_block" => { "field_summary_input" => { "value" => "Duplicate of INC-041." } } }
    ))

    assert_equal "Duplicate of INC-041.", @incident.reload.summary
  end

  test "opens a modal instead when the workspace has attached a field" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_CANCEL)
    IncidentFormService.new(@workspace).add_custom_field(form, incident_field_definitions(:customer_tier_ws1))

    ModalOpener.expects(:open).once
    assert_nil Commands::CancelIncident.execute(command)

    assert_not_equal @canceled.id, @incident.reload.incident_status_id
  end
end
