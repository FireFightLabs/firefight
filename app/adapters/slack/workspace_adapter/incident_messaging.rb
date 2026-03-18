module Slack::WorkspaceAdapter::IncidentMessaging
  extend ActiveSupport::Concern

  TIMELINE_DEFAULT_LIMIT = 15
  TIMELINE_PAGE_SIZE = 15
  TIMELINE_MAX_EVENTS = 45

  def update_incident_quick_actions(channel_id:, ts:, incident:)
    blocks = Slack::IncidentMessageBuilder.quick_actions_blocks(incident)
    update_message(
      channel_id: channel_id,
      ts: ts,
      text: "#{incident.identifier} - Quick Actions",
      blocks: blocks
    )
  end

  def update_incident_announcement(channel_id:, ts:, incident:)
    blocks = Slack::IncidentMessageBuilder.announcement_blocks(incident)
    update_message(
      channel_id: channel_id,
      ts: ts,
      text: "New incident: #{incident.identifier}",
      blocks: blocks
    )
  end

  def post_lead_expectations(channel_id:, user_id:)
    blocks = [
      {
        type: "header",
        text: { type: "plain_text", text: ":firefighter: You are now the Incident Lead", emoji: true }
      },
      {
        type: "section",
        text: { type: "mrkdwn", text: "*Here's what's expected:*" }
      },
      {
        type: "section",
        text: { type: "mrkdwn", text: "\u2022 Own the incident and drive resolution\n\u2022 Keep communication clear and frequent\n\u2022 Make sure everyone knows what to do" }
      },
      {
        type: "context",
        elements: [ { type: "mrkdwn", text: "You've got this :muscle:" } ]
      }
    ]
    post_ephemeral(channel_id: channel_id, user_id: user_id, text: "You are now the Incident Lead", blocks: blocks)
  end

  def post_incident_quick_actions(channel_id:, incident:)
    blocks = Slack::IncidentMessageBuilder.quick_actions_blocks(incident)
    post_message(
      channel_id: channel_id,
      text: "#{incident.identifier} - Quick Actions",
      blocks: blocks
    )
  end

  def post_incident_announcement(channel_id:, incident:)
    blocks = Slack::IncidentMessageBuilder.announcement_blocks(incident)
    post_message(
      channel_id: channel_id,
      text: "New incident: #{incident.identifier}",
      blocks: blocks
    )
  end

  def post_incident_update_message(channel_id:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
    blocks = Slack::IncidentMessageBuilder.status_update_blocks(
      incident,
      message: message,
      updated_by_platform_user_id: updated_by_platform_user_id,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name,
      previous_type_name: previous_type_name
    )
    post_message(channel_id: channel_id, text: "Incident updated", blocks: blocks)
  end

  def post_incident_update_announcement_thread(channel_id:, thread_ts:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
    blocks = Slack::IncidentMessageBuilder.status_update_announcement_blocks(
      incident,
      message: message,
      updated_by_platform_user_id: updated_by_platform_user_id,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name,
      previous_type_name: previous_type_name
    )
    post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: "Incident updated", blocks: blocks)
  end

  def post_incident_update_reminder(channel_id:, user_id:, incident:)
    blocks = Slack::IncidentMessageBuilder.update_reminder_blocks(incident)
    post_ephemeral(
      channel_id: channel_id,
      user_id: user_id,
      text: "It's time to provide a status update for #{incident.identifier}",
      blocks: blocks
    )
  end

  def format_incident_list_line(incident)
    lead = incident.lead ? "<@#{incident.lead.platform_user_id}>" : "Unassigned"
    channel = if incident.channel_id.present?
      "<##{incident.channel_id}>"
    elsif incident.is_private?
      "Private channel"
    else
      "No channel"
    end

    [
      "> *#{incident.identifier}* #{incident.name || 'Untitled Incident'}",
      "> #{incident.incident_severity.name} | #{incident.incident_status.name} | Lead: #{lead} | #{channel}"
    ].join("\n")
  end

  def open_timeline_modal(trigger_id:, incident:, limit: TIMELINE_DEFAULT_LIMIT)
    view = build_timeline_view(incident, limit: limit)
    return unless view

    open_modal(trigger_id: trigger_id, view: view)
  end

  def push_timeline_modal(trigger_id:, incident:, limit: TIMELINE_DEFAULT_LIMIT)
    view = build_timeline_view(incident, limit: limit)
    return unless view

    push_modal(trigger_id: trigger_id, view: view)
  end

  def update_timeline_modal(view_id:, incident:, limit: TIMELINE_DEFAULT_LIMIT)
    view = build_timeline_view(incident, limit: limit)
    return unless view

    translate_errors do
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

  def post_resolution_message(channel_id:, incident:, resolved_by_platform_user_id:)
    blocks = Slack::IncidentMessageBuilder.resolution_blocks(incident, resolved_by_platform_user_id: resolved_by_platform_user_id)
    post_message(channel_id: channel_id, text: "Incident resolved", blocks: blocks)
  end

  def post_resolution_announcement_thread(channel_id:, thread_ts:, incident:, resolved_by_platform_user_id:)
    blocks = Slack::IncidentMessageBuilder.resolution_announcement_thread_blocks(incident, resolved_by_platform_user_id: resolved_by_platform_user_id)
    post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: "Incident resolved", blocks: blocks)
  end

  def post_related_link_message(channel_id:, source:, target:, linked_by_platform_user_id:)
    blocks = Slack::IncidentMessageBuilder.related_link_blocks(source, target, linked_by_platform_user_id: linked_by_platform_user_id)
    post_message(channel_id: channel_id, text: "Incident linked", blocks: blocks)
  end

  def post_duplicate_source_message(channel_id:, source:, canonical:, linked_by_platform_user_id:)
    blocks = Slack::IncidentMessageBuilder.duplicate_source_blocks(source, canonical, linked_by_platform_user_id: linked_by_platform_user_id)
    post_message(channel_id: channel_id, text: "Incident merged", blocks: blocks)
  end

  def post_duplicate_canonical_message(channel_id:, source:, canonical:, linked_by_platform_user_id:)
    blocks = Slack::IncidentMessageBuilder.duplicate_canonical_blocks(source, canonical, linked_by_platform_user_id: linked_by_platform_user_id)
    post_message(channel_id: channel_id, text: "Duplicate merged in", blocks: blocks)
  end

  def post_reopen_message(channel_id:, incident:, reopened_by_platform_user_id:, reason: nil)
    blocks = Slack::IncidentMessageBuilder.reopen_blocks(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reason: reason)
    post_message(channel_id: channel_id, text: "Incident reopened", blocks: blocks)
  end

  def post_reopen_announcement_thread(channel_id:, thread_ts:, incident:, reopened_by_platform_user_id:, reason: nil)
    blocks = Slack::IncidentMessageBuilder.reopen_announcement_thread_blocks(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reason: reason)
    post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: "Incident reopened", blocks: blocks)
  end

  def post_escalation_message(channel_id:, incident:, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
    blocks = Slack::IncidentMessageBuilder.escalation_blocks(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalated_to_platform_user_id: escalated_to_platform_user_id,
      reason: reason
    )
    post_message(channel_id: channel_id, text: "Incident escalated", blocks: blocks)
  end

  def post_escalation_announcement_thread(channel_id:, thread_ts:, incident:, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
    blocks = Slack::IncidentMessageBuilder.escalation_announcement_thread_blocks(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalated_to_platform_user_id: escalated_to_platform_user_id,
      reason: reason
    )
    post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: "Incident escalated", blocks: blocks)
  end

  def post_escalation_direct_message(user_id:, incident:, escalated_by_platform_user_id:, escalation_event_id:, reason: nil)
    blocks = Slack::IncidentMessageBuilder.escalation_direct_message_blocks(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalation_event_id: escalation_event_id,
      reason: reason
    )
    post_message(channel_id: user_id, text: "Incident escalated to you", blocks: blocks)
  end

  def post_escalation_acknowledged_message(channel_id:, incident:, acknowledged_by_platform_user_id:, escalated_to_platform_user_id:)
    blocks = Slack::IncidentMessageBuilder.escalation_acknowledged_blocks(
      incident,
      acknowledged_by_platform_user_id: acknowledged_by_platform_user_id,
      escalated_to_platform_user_id: escalated_to_platform_user_id
    )
    post_message(channel_id: channel_id, text: "Escalation acknowledged", blocks: blocks)
  end

  def post_escalation_nudge_direct_message(user_id:, incident:, escalated_by_platform_user_id:, escalation_event_id:, reason: nil)
    blocks = Slack::IncidentMessageBuilder.escalation_nudge_direct_message_blocks(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalation_event_id: escalation_event_id,
      reason: reason
    )
    post_message(channel_id: user_id, text: "Reminder to acknowledge escalation", blocks: blocks)
  end

  def post_action_message(channel_id:, action:)
    type_label = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
    blocks = Slack::IncidentMessageBuilder.action_created_blocks(action)
    post_message(channel_id: channel_id, text: "New #{type_label} added", blocks: blocks)
  end

  def update_action_picked_up(channel_id:, ts:, action:)
    blocks = Slack::IncidentMessageBuilder.action_picked_up_blocks(action)
    type_label = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
    update_message(channel_id: channel_id, ts: ts, text: "#{type_label.capitalize} updated", blocks: blocks)
  end

  def update_action_completed(channel_id:, ts:, action:)
    blocks = Slack::IncidentMessageBuilder.action_completed_blocks(action)
    type_label = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
    update_message(channel_id: channel_id, ts: ts, text: "#{type_label.capitalize} updated", blocks: blocks)
  end

  def post_shoutout_message(channel_id:, incident:, from_user_id:, recipient_user_id:, message:)
    blocks = Slack::IncidentMessageBuilder.shoutout_blocks(
      incident,
      from_user_id: from_user_id,
      recipient_user_id: recipient_user_id,
      message: message
    )
    post_message(channel_id: channel_id, text: ":heart_on_fire: Shoutout in #{incident.identifier}", blocks: blocks)
  end

  def post_shoutout_from_reaction_prompt(channel_id:, user_id:, incident_id:)
    blocks = Slack::IncidentMessageBuilder.shoutout_from_reaction_blocks(incident_id)
    post_ephemeral(
      channel_id: channel_id,
      user_id: user_id,
      text: "Give a shoutout?",
      blocks: blocks
    )
  end

  def post_action_from_reaction_prompt(channel_id:, user_id:, action_type:, message_text:, incident_id:, source_message_link:)
    blocks = Slack::IncidentMessageBuilder.action_from_reaction_blocks(
      action_type, message_text, incident_id, source_message_link
    )
    type_label = action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
    post_ephemeral(
      channel_id: channel_id,
      user_id: user_id,
      text: "Create #{type_label} from this message?",
      blocks: blocks
    )
  end

  def build_timeline_view(incident, limit: TIMELINE_DEFAULT_LIMIT)
    capped_limit = [ [ limit.to_i, TIMELINE_DEFAULT_LIMIT ].max, TIMELINE_MAX_EVENTS ].min
    events = incident.incident_events.includes(:eventable).recent.limit(capped_limit).reverse
    return nil if events.empty?

    lead_text = incident.lead ? "<@#{incident.lead.platform_user_id}>" : "Unassigned"
    detail_lines = [
      "*#{incident.identifier}* · #{incident.name}",
      "#{incident.incident_severity.name} · #{incident.incident_status.name} · Lead: #{lead_text}"
    ]
    detail_lines << "_#{incident.summary}_" if incident.summary.present?

    blocks = [
      { type: "section", text: { type: "mrkdwn", text: detail_lines.join("\n") } },
      { type: "divider" }
    ]
    blocks.concat(Slack::IncidentTimelineFormatter.to_blocks(events))

    total_events = incident.incident_events.count
    if total_events > capped_limit
      blocks << { type: "actions", elements: [ timeline_load_more_button(incident.id, capped_limit) ] }
      blocks << {
        type: "context",
        elements: [ { type: "mrkdwn", text: "Showing latest #{capped_limit} of #{total_events} events" } ]
      }
    end

    title = "#{incident.identifier} Timeline"
    title = title[0, 24] if title.length > 24

    {
      type: "modal",
      callback_id: Identifiers::TIMELINE_MODAL,
      title: { type: "plain_text", text: title, emoji: true },
      close: { type: "plain_text", text: "Close", emoji: true },
      blocks: blocks
    }
  end

  private

  def timeline_load_more_button(incident_id, current_limit)
    {
      type: "button",
      text: { type: "plain_text", text: "Load more", emoji: true },
      action_id: Identifiers::LOAD_MORE_TIMELINE,
      value: {
        incident_id: incident_id,
        limit: [ current_limit + TIMELINE_PAGE_SIZE, TIMELINE_MAX_EVENTS ].min
      }.to_json
    }
  end
end
