class IncidentCreationWorkflow < Base
  workflow_name "incident.creation.v1"

  step :create_slack_channel
  step :set_channel_metadata, depends_on: [ :create_slack_channel ]
  step :post_quick_actions_message, depends_on: [ :set_channel_metadata ]
  step :post_announcement, depends_on: [ :create_slack_channel ]
  step :invite_declarer, depends_on: [ :create_slack_channel ]
  step :create_incident_event

  def create_slack_channel(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace
    adapter = Slack::WorkspaceAdapter.new(workspace)

    result = adapter.create_channel(
      name: incident.channel_name,
      is_private: incident.is_private
    )

    incident.update!(
      slack_channel_id: result[:channel_id],
      slack_channel_name: result[:channel_name]
    )

    { channel_id: result[:channel_id] }
  rescue Slack::Client::ChannelExistsError
    fallback_name = "#{incident.channel_name}-#{Time.current.to_i}"
    result = adapter.create_channel(name: fallback_name, is_private: incident.is_private)

    incident.update!(
      slack_channel_id: result[:channel_id],
      slack_channel_name: result[:channel_name]
    )

    { channel_id: result[:channel_id] }
  end

  def set_channel_metadata(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace
    channel_id = input["create_slack_channel"]["channel_id"]

    topic = "Severity: #{incident.incident_severity.name} | Status: #{incident.incident_status.name}"
    purpose = "Incident response channel for #{incident.identifier}"

    Slack::Client.set_channel_topic(workspace: workspace, channel: channel_id, topic: topic)
    Slack::Client.set_channel_purpose(workspace: workspace, channel: channel_id, purpose: purpose)

    { ok: true }
  end

  def post_quick_actions_message(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace
    blocks = Slack::IncidentMessageBuilder.quick_actions_blocks(incident)

    result = Slack::Client.post_message(
      workspace: workspace,
      channel: incident.slack_channel_id,
      text: "#{incident.identifier} - Quick Actions",
      blocks: blocks
    )

    Slack::Client.pin_message(
      workspace: workspace,
      channel: incident.slack_channel_id,
      timestamp: result[:ts]
    )

    incident.update!(initial_message_ts: result[:ts])

    { message_ts: result[:ts] }
  end

  def post_announcement(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace
    incidents_channel_id = workspace.incidents_channel_id

    return { skipped: true } unless incidents_channel_id

    blocks = Slack::IncidentMessageBuilder.announcement_blocks(incident)

    result = Slack::Client.post_message(
      workspace: workspace,
      channel: incidents_channel_id,
      text: "New incident: #{incident.identifier}",
      blocks: blocks
    )

    incident.update!(announcement_message_ts: result[:ts])

    { message_ts: result[:ts] }
  end

  def invite_declarer(workflow:, step:, input:)
    incident = workflow.subject
    workspace = incident.workspace

    Slack::Client.invite_to_channel(
      workspace: workspace,
      channel: incident.slack_channel_id,
      users: incident.declared_by.platform_user_id
    )

    { ok: true }
  end

  def create_incident_event(workflow:, step:, input:)
    incident = workflow.subject

    IncidentEvent.create!(
      incident: incident,
      user: incident.declared_by,
      event_type: IncidentEvent::INCIDENT_CREATED,
      metadata: {
        "severity" => incident.incident_severity.slug,
        "is_private" => incident.is_private
      }
    )

    { ok: true }
  end
end
