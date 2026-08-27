require "test_helper"

# An agent doing the work of an incident rather than only opening and closing
# one: raising items, taking them, finishing them, pulling people in, and
# saying thank you. Every tool goes through the same service the Slack button
# and the dashboard use.
class McpIncidentParticipationToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @other = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)

    _, @personal_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )
    @agent, @agent_token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Support agent", slug: "support_agent",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create update] }
    )

    stub_post_message
    stub_update_message
    stub_post_ephemeral
    stub_invite_to_channel
    stub_set_channel_topic
    stub_set_channel_purpose
  end

  test "every participation tool is offered as a write" do
    tools = rpc("tools/list").dig("result", "tools").index_by { |tool| tool["name"] }

    [ Mcp::Tools::CREATE_ACTION_ITEM, Mcp::Tools::ASSIGN_ACTION_ITEM, Mcp::Tools::COMPLETE_ACTION_ITEM,
      Mcp::Tools::CLAIM_RUNBOOK_STEP, Mcp::Tools::LINK_INCIDENT, Mcp::Tools::GIVE_SHOUTOUT,
      Mcp::Tools::ESCALATE_INCIDENT, Mcp::Tools::INVITE_RESPONDERS ].each do |name|
      assert tools[name], "#{name} should be offered"
      assert_not tools[name].dig("annotations", "readOnlyHint"), "#{name} should not be read-only"
    end
  end

  # An agent has to be able to name the work before it can act on it.
  test "get_incident names the action items and runbook steps by id" do
    action = incident_actions(:inc1_action_open)
    content, = call_tool(Mcp::Tools::GET_INCIDENT, { incident: @incident.identifier })

    listed = content["action_items"].index_by { |item| item["id"] }
    assert listed[action.id], "the open item should be listed"
    assert_equal action.description, listed[action.id]["description"]
    assert content.key?("runbooks")
  end

  test "an agent raises an action item and is recorded as having raised it" do
    content, is_error = call_tool(Mcp::Tools::CREATE_ACTION_ITEM, {
      incident: @incident.identifier, description: "Drain replica 2", kind: IncidentAction::ACTION_TYPE_ACTION
    }, token: @agent_token)

    assert_not is_error, content.inspect
    action = @incident.incident_actions.find_by!(description: "Drain replica 2")
    assert_equal @agent, action.created_by
    assert_equal IncidentAction::STATUS_OPEN, action.status
  end

  test "an agent takes an item and holds it under its own name" do
    action = incident_actions(:inc1_followup)

    content, is_error = call_tool(Mcp::Tools::ASSIGN_ACTION_ITEM, {
      incident: @incident.identifier, action_item: action.id
    }, token: @agent_token)

    assert_not is_error, content.inspect
    assert_equal @agent, action.reload.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, action.status
    assert_equal @agent.name, content["assignee"]
  end

  test "an agent hands an item to a person" do
    action = incident_actions(:inc1_action_in_progress)

    _, is_error = call_tool(Mcp::Tools::ASSIGN_ACTION_ITEM, {
      incident: @incident.identifier, action_item: action.id, member: @other.user.email
    }, token: @agent_token)

    assert_not is_error
    assert_equal @other, action.reload.assignee
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_REASSIGNED)
  end

  test "an agent finishes an item and the timeline names the agent" do
    action = incident_actions(:inc1_action_open)

    _, is_error = call_tool(Mcp::Tools::COMPLETE_ACTION_ITEM, {
      incident: @incident.identifier, action_item: action.id
    }, token: @agent_token)

    assert_not is_error
    assert action.reload.done?
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_COMPLETED)
    assert_equal @agent, event.actor
  end

  test "finishing something already finished says so rather than doing nothing" do
    action = incident_actions(:inc1_action_open)
    action.update!(status: IncidentAction::STATUS_DONE)

    _, is_error, text = call_tool(Mcp::Tools::COMPLETE_ACTION_ITEM, {
      incident: @incident.identifier, action_item: action.id
    })

    assert is_error
    assert_match(/already done/, text)
  end

  test "an agent claims a runbook step, which opens the item behind it" do
    attachment = attach_runbook

    content, is_error = call_tool(Mcp::Tools::CLAIM_RUNBOOK_STEP, {
      incident: @incident.identifier,
      runbook: attachment.id,
      step: attachment.runbook.runbook_steps.first.id
    }, token: @agent_token)

    assert_not is_error, content.inspect
    action = @incident.incident_actions.active.find_by!(runbook_step: attachment.runbook.runbook_steps.first)
    assert_equal @agent, action.assignee
  end

  test "an agent links two incidents and both timelines say so" do
    other = incidents(:active_major_ws1)

    _, is_error = call_tool(Mcp::Tools::LINK_INCIDENT, {
      incident: @incident.identifier, other_incident: other.identifier,
      relationship: IncidentRelationship::RELATED
    }, token: @agent_token)

    assert_not is_error
    assert @incident.incident_events.exists?(event_type: IncidentEvent::RELATIONSHIP_CREATED)
    assert other.incident_events.exists?(event_type: IncidentEvent::RELATIONSHIP_CREATED)
  end

  test "marking a duplicate cancels this incident into the other one" do
    other = incidents(:active_major_ws1)

    _, is_error = call_tool(Mcp::Tools::LINK_INCIDENT, {
      incident: @incident.identifier, other_incident: other.identifier,
      relationship: IncidentRelationship::DUPLICATE
    }, token: @agent_token)

    assert_not is_error
    assert @incident.reload.canceled?
    assert @incident.incident_events.exists?(event_type: IncidentEvent::MERGED_INTO)
  end

  test "an incident cannot be linked to itself" do
    _, is_error, text = call_tool(Mcp::Tools::LINK_INCIDENT, {
      incident: @incident.identifier, other_incident: @incident.identifier,
      relationship: IncidentRelationship::RELATED
    })

    assert is_error
    assert_match(/must be a different incident/, text)
  end

  test "an agent thanks someone and the shoutout names the agent" do
    _, is_error = call_tool(Mcp::Tools::GIVE_SHOUTOUT, {
      incident: @incident.identifier, member: @other.user.email, message: "Found the leak in minutes"
    }, token: @agent_token)

    assert_not is_error
    shoutout = @incident.shoutouts.find_by!(to_member_id: @other.id)
    assert_equal @agent, shoutout.from_member
  end

  # The point of escalation from an agent: it has gone as far as it can and
  # needs a named human.
  test "an agent escalates to a person and the chase is scheduled" do
    assert_enqueued_with(job: EscalationAcknowledgementReminderJob) do
      _, is_error = call_tool(Mcp::Tools::ESCALATE_INCIDENT, {
        incident: @incident.identifier, member: @other.user.email, reason: "Needs a database owner"
      }, token: @agent_token)

      assert_not is_error
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_ESCALATED)
    assert_equal @agent, event.actor
    assert_equal @other.id, event.metadata["escalated_to_member_id"]
    assert_equal "Needs a database owner", event.metadata["reason"]
  end

  test "an incident that is over cannot be escalated" do
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @membership
    )

    _, is_error, text = call_tool(Mcp::Tools::ESCALATE_INCIDENT, {
      incident: @incident.identifier, member: @other.user.email, reason: "Too late"
    })

    assert is_error
    assert_match(/no longer be escalated/, text)
  end

  test "an agent invites people by email and gets back their names" do
    content, is_error = call_tool(Mcp::Tools::INVITE_RESPONDERS, {
      incident: @incident.identifier, members: [ @other.user.email ]
    }, token: @agent_token)

    assert_not is_error, content.inspect
    assert_equal [ @other.display_name ], content["invited"]
  end

  test "inviting somebody this workspace has never heard of says so" do
    _, is_error, text = call_tool(Mcp::Tools::INVITE_RESPONDERS, {
      incident: @incident.identifier, members: [ "nobody@example.com" ]
    })

    assert is_error
    assert_match(/Not found in this workspace/, text)
  end

  # The guard lives on the incident and the service refuses, so a surface that
  # never thought to ask still cannot post into a channel that is gone.
  test "an incident that is over refuses an invite and a shoutout" do
    close_incident

    _, is_error, text = call_tool(Mcp::Tools::INVITE_RESPONDERS, {
      incident: @incident.identifier, members: [ @other.user.email ]
    })
    assert is_error
    assert_match(/nobody else can be brought into it/, text)

    _, is_error, text = call_tool(Mcp::Tools::GIVE_SHOUTOUT, {
      incident: @incident.identifier, member: @other.user.email, message: "Nice work"
    })
    assert is_error
    assert_match(/shoutouts can no longer be posted/, text)
    assert_empty @incident.shoutouts
  end

  test "an incident whose channel is still being created refuses both too" do
    @incident.update_columns(channel_id: nil)

    _, is_error, text = call_tool(Mcp::Tools::INVITE_RESPONDERS, {
      incident: @incident.identifier, members: [ @other.user.email ]
    })
    assert is_error
    assert_match(/no channel yet/, text)

    _, is_error, text = call_tool(Mcp::Tools::GIVE_SHOUTOUT, {
      incident: @incident.identifier, member: @other.user.email, message: "Nice work"
    })
    assert is_error
    assert_match(/no channel yet/, text)
  end

  # Claiming a step nobody holds is taking it, whichever door you came through.
  test "claiming an unheld step records a pick up rather than a handover" do
    attachment = attach_runbook
    step = attachment.runbook.runbook_steps.first
    IncidentActionService.new(@workspace).assign_step(
      incident: @incident, runbook_step: step, assignee: @other, assigned_by: @membership
    )
    @incident.incident_actions.active.find_by!(runbook_step: step).update!(
      assignee: nil, status: IncidentAction::STATUS_OPEN
    )

    content, is_error = call_tool(Mcp::Tools::CLAIM_RUNBOOK_STEP, {
      incident: @incident.identifier, runbook: attachment.id, step: step.id
    }, token: @agent_token)

    assert_not is_error, content.inspect
    assert_equal @agent.name, content["assignee"]
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_PICKED_UP)
  end

  test "a person this workspace has never heard of is named, not silently dropped" do
    _, is_error, text = call_tool(Mcp::Tools::CREATE_ACTION_ITEM, {
      incident: @incident.identifier, description: "Page somebody", member: "nobody@example.com"
    })

    assert is_error
    assert_match(/Not found in this workspace/, text)
    assert_nil @incident.incident_actions.find_by(description: "Page somebody")
  end

  test "an agent granted only reads cannot raise an action item" do
    _, token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Watcher", slug: "watcher",
      permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read] }
    )

    _, is_error = call_tool(Mcp::Tools::CREATE_ACTION_ITEM, {
      incident: @incident.identifier, description: "Should never exist"
    }, token: token)

    assert is_error
    assert_nil @incident.incident_actions.find_by(description: "Should never exist")
  end

  private

  def close_incident
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @membership
    )
  end

  def attach_runbook
    runbook = @workspace.runbooks.create!(name: "Database failover", slug: "database_failover")
    runbook.runbook_steps.create!(title: "Drain the primary", position: 1)

    RunbookAttachmentService.new(@workspace).attach_by_slug(
      incident: @incident, slug: runbook.slug, attached_by: @membership
    )
  end

  def rpc(method, params = {}, id: 1, token: @personal_token)
    post mcp_path,
         params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    JSON.parse(response.body)
  end

  def call_tool(name, arguments = {}, token: @personal_token)
    result = rpc("tools/call", { name: name, arguments: arguments }, token: token).fetch("result")
    [ result["structuredContent"] || {}, result["isError"], result.dig("content", 0, "text") ]
  end
end
