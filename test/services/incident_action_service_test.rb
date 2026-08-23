require "test_helper"

class IncidentActionServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
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
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )

    @service = IncidentActionService.new(@workspace)
    stub_get_permalink
  end

  test "create_action creates record and posts message" do
    stub_post_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Restart the service"
    )

    assert_equal "action", action.action_type
    assert_equal "Restart the service", action.description
    assert_equal IncidentAction::STATUS_OPEN, action.status
    assert_equal @member, action.created_by
    assert_nil action.assignee
    assert_equal "1234567890.123456", action.message_ts
  end

  test "create_action with assignee" do
    stub_post_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Check logs",
      assignee: @bob
    )

    assert_equal @bob, action.assignee
  end

  test "create_action creates followup type" do
    stub_post_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_FOLLOWUP,
      description: "Add monitoring alerts"
    )

    assert_equal "followup", action.action_type
  end

  test "create_action creates incident event with action update" do
    stub_post_message

    assert_difference [ "IncidentEvent.count", "IncidentActionUpdate.count" ], 1 do
      @service.create_action(
        incident: @incident,
        created_by: @member,
        action_type: IncidentAction::ACTION_TYPE_ACTION,
        description: "Restart the service"
      )
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_CREATED)
    assert_equal @member, event.actor
    assert_instance_of IncidentActionUpdate, event.eventable

    action_update = event.eventable
    assert_equal IncidentActionUpdate::CREATED, action_update.update_type
    assert_equal "action", action_update.action_type
    assert_equal @incident, action_update.incident
    assert_equal @member, action_update.created_by
    assert_equal "Restart the service", action_update.description
    assert_equal IncidentAction::STATUS_OPEN, action_update.status
    assert_equal [], action_update.changed_fields
  end

  test "create_action stores platform_data" do
    stub_post_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "From reaction",
      platform_data: { source_message_link: "https://example.com/message" }
    )

    assert_equal "https://example.com/message", action.platform_data["source_message_link"]
  end

  test "pick_up_action assigns and updates status" do
    stub_post_message
    stub_update_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue"
    )

    @service.pick_up_action(action: action, picked_up_by: @bob)

    action.reload
    assert_equal @bob, action.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, action.status
  end

  test "pick_up_action creates incident event with action update" do
    stub_post_message
    stub_update_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue"
    )

    assert_difference [ "IncidentEvent.count", "IncidentActionUpdate.count" ], 1 do
      @service.pick_up_action(action: action, picked_up_by: @bob)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_PICKED_UP)
    assert_equal @bob, event.actor
    assert_instance_of IncidentActionUpdate, event.eventable

    action_update = event.eventable
    assert_equal IncidentActionUpdate::PICKED_UP, action_update.update_type
    assert_equal @bob, action_update.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, action_update.status
    assert_includes action_update.changed_fields, "assignee"
    assert_includes action_update.changed_fields, "status"
  end

  test "complete_action sets done status" do
    stub_post_message
    stub_update_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue",
      assignee: @bob
    )

    @service.pick_up_action(action: action, picked_up_by: @bob)
    @service.complete_action(action: action, completed_by: @bob)

    action.reload
    assert_equal IncidentAction::STATUS_DONE, action.status
  end

  test "complete_action creates incident event with action update" do
    stub_post_message
    stub_update_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue",
      assignee: @bob
    )

    @service.pick_up_action(action: action, picked_up_by: @bob)

    assert_difference [ "IncidentEvent.count", "IncidentActionUpdate.count" ], 1 do
      @service.complete_action(action: action, completed_by: @bob)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_COMPLETED)
    assert_equal @bob, event.actor
    assert_instance_of IncidentActionUpdate, event.eventable

    action_update = event.eventable
    assert_equal IncidentActionUpdate::COMPLETED, action_update.update_type
    assert_equal IncidentAction::STATUS_DONE, action_update.status
    assert_includes action_update.changed_fields, "status"
  end

  test "reassign_action moves the item and posts a line so the new holder hears about it" do
    stub_post_message
    stub_update_message
    action = @service.create_action(
      incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Check logs", assignee: @member
    )

    @service.reassign_action(action: action, assignee: @bob, reassigned_by: @member)

    assert_equal @bob, action.reload.assignee
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_REASSIGNED)
  end

  test "reassign_action leaves a completed item alone" do
    stub_post_message
    stub_update_message
    action = @service.create_action(
      incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Check logs", assignee: @member
    )
    @service.complete_action(action: action, completed_by: @member)

    @service.reassign_action(action: action, assignee: @bob, reassigned_by: @member)

    assert_equal @member, action.reload.assignee
  end

  test "reassign_action to the current holder does nothing" do
    stub_post_message
    stub_update_message
    action = @service.create_action(
      incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Check logs", assignee: @member
    )

    assert_no_difference -> { @incident.incident_events.where(event_type: IncidentEvent::ACTION_REASSIGNED).count } do
      @service.reassign_action(action: action, assignee: @member, reassigned_by: @bob)
    end
  end

  test "taking a step yourself creates the action and posts nothing" do
    step = @workspace.runbooks.create!(name: "Runbook").runbook_steps.create!(title: "Check the pool", position: 1)
    Slack::Client.expects(:post_message).never

    action = @service.assign_step(incident: @incident, runbook_step: step, assignee: @member, assigned_by: @member)

    assert_equal step, action.runbook_step
    assert_equal @member, action.assignee
    assert_nil action.message_ts
  end

  test "handing a step to someone else posts a card the new holder can act on" do
    step = @workspace.runbooks.create!(name: "Runbook").runbook_steps.create!(title: "Check the pool", position: 1)
    Slack::Client.expects(:post_message).once.returns({ ok: true, ts: "1.1" })

    action = @service.assign_step(incident: @incident, runbook_step: step, assignee: @bob, assigned_by: @member)

    assert_equal @bob, action.assignee
    assert_equal "1.1", action.message_ts, "the handover post becomes the item's own message"
  end

  test "assigning a step someone already holds hands it over rather than duplicating it" do
    step = @workspace.runbooks.create!(name: "Runbook").runbook_steps.create!(title: "Check the pool", position: 1)
    @service.assign_step(incident: @incident, runbook_step: step, assignee: @member, assigned_by: @member)
    Slack::Client.expects(:post_message).at_least_once.returns({ ok: true, ts: "1.1" })

    assert_no_difference "@incident.incident_actions.count" do
      @service.assign_step(incident: @incident, runbook_step: step, assignee: @bob, assigned_by: @member)
    end

    assert_equal @bob, @incident.incident_actions.find_by!(runbook_step: step).assignee
  end

  test "completing an item posts a notice linking back to where it came from" do
    stub_post_message
    stub_update_message
    action = @service.create_action(
      incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Restart the worker", assignee: @member
    )

    posted = []
    Slack::Client.stubs(:post_message).with { |args| posted << args }.returns({ ok: true, ts: "9.9" })

    @service.complete_action(action: action, completed_by: @member)

    notice = posted.last
    assert_includes notice[:text], "Action completed"
    assert_includes notice[:blocks].to_s, "Restart the worker"
    assert_includes notice[:blocks].to_s, "Completed by"
  end

  test "a completed runbook step points back at the runbook rather than a card it never had" do
    stub_post_message
    stub_update_message
    runbook = @workspace.runbooks.create!(name: "Database outage")
    step = runbook.runbook_steps.create!(title: "Check the pool", position: 1)
    @incident.incident_runbooks.create!(runbook: runbook, workspace: @workspace, message_ts: "5.5")
    action = @service.assign_step(incident: @incident, runbook_step: step, assignee: @member, assigned_by: @member)

    posted = []
    Slack::Client.stubs(:post_message).with { |args| posted << args }.returns({ ok: true, ts: "9.9" })

    @service.complete_action(action: action, completed_by: @member)

    assert_includes posted.last[:blocks].to_s, "Database outage"
  end

  test "a permalink failure does not stop the completion being announced" do
    stub_post_message
    stub_update_message
    action = @service.create_action(
      incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Restart the worker", assignee: @member
    )
    Slack::Client.stubs(:get_permalink).raises(AdapterError.new("boom"))

    posted = []
    Slack::Client.stubs(:post_message).with { |args| posted << args }.returns({ ok: true, ts: "9.9" })

    @service.complete_action(action: action, completed_by: @member)

    assert_includes posted.last[:text], "Action completed"
  end

  # An item that already has controls in the channel must not get a second set,
  # because only the first is ever updated and the other keeps a live button on
  # finished work.
  test "handing over an item that already has a message points at it instead of duplicating its controls" do
    stub_post_message
    stub_update_message
    action = @service.create_action(
      incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Restart the worker", assignee: @member
    )
    original_ts = action.message_ts

    posted = []
    Slack::Client.stubs(:post_message).with { |args| posted << args }.returns({ ok: true, ts: "SECOND" })

    @service.reassign_action(action: action, assignee: @bob, reassigned_by: @member)

    assert_equal 1, posted.size
    assert_not_includes posted.first[:blocks].to_s, Identifiers::MARK_ACTION_DONE
    assert_equal original_ts, action.reload.message_ts, "the item keeps the one message that carries its controls"
  end

  test "handing over an item with no message of its own gives it one, controls and all" do
    stub_post_message
    stub_update_message
    step = @workspace.runbooks.create!(name: "Runbook").runbook_steps.create!(title: "Check the pool", position: 1)
    action = @service.assign_step(incident: @incident, runbook_step: step, assignee: @member, assigned_by: @member)
    assert_nil action.message_ts

    Slack::Client.stubs(:post_message).returns({ ok: true, ts: "ADOPTED" })
    @service.reassign_action(action: action, assignee: @bob, reassigned_by: @member)

    assert_equal "ADOPTED", action.reload.message_ts
  end
end
