module Slack::WorkspaceAdapter::IncidentMessaging
  extend ActiveSupport::Concern

  # Two blocks per event against Slack's 100-block modal ceiling, leaving room
  # for the header, the divider, the pager and its caption.
  TIMELINE_PAGE_SIZE = 45

  def post_alert_message(channel_id:, alert:)
    blocks = Slack::Messages::Alert.build(alert)
    post_message(channel_id: channel_id, text: Slack::Mrkdwn.escape(alert.title), blocks: blocks)
  end

  def post_routing_test_message(channel_id:, description:)
    blocks = [
      { type: "section", text: { type: "mrkdwn", text: ":test_tube:  *Routing test:* #{description}" } },
      {
        type: "context",
        elements: [ { type: "mrkdwn", text: "Sent from the alert routing tester. No incident was created and no action is needed." } ]
      }
    ]
    post_message(channel_id: channel_id, text: "Routing test: #{description}", blocks: blocks)
  end

  def update_alert_message(channel_id:, message_id:, alert:)
    blocks = Slack::Messages::Alert.build(alert)
    update_message(
      channel_id: channel_id,
      message_id: message_id,
      text: Slack::Mrkdwn.escape(alert.title),
      blocks: blocks
    )
  end

  def update_incident_quick_actions(channel_id:, message_id:, incident:)
    blocks = Slack::Messages::QuickActions.build(incident)
    update_message(
      channel_id: channel_id,
      message_id: message_id,
      text: "#{incident.identifier} - Quick Actions",
      blocks: blocks
    )
  end

  def update_incident_announcement(channel_id:, message_id:, incident:)
    blocks = Slack::Messages::Announcement.build(incident)
    update_message(
      channel_id: channel_id,
      message_id: message_id,
      text: "New incident: #{incident.identifier}",
      blocks: blocks
    )
  end

  def post_role_announcement(channel_id:, changes:)
    post_message(
      channel_id: channel_id,
      text: "Incident roles updated: #{Slack::Messages::RoleAssignment.summary_text(changes)}",
      blocks: Slack::Messages::RoleAssignment.announcement(changes)
    )
  end

  def post_lead_announcement(channel_id:, lead_platform_user_id:)
    blocks = Slack::Messages::LeadAssignment.announcement(lead_platform_user_id: lead_platform_user_id)
    post_message(
      channel_id: channel_id,
      text: "<@#{lead_platform_user_id}> is now the Incident Lead",
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
    blocks = Slack::Messages::QuickActions.build(incident)
    post_message(
      channel_id: channel_id,
      text: "#{incident.identifier} - Quick Actions",
      blocks: blocks
    )
  end

  def post_incident_announcement(channel_id:, incident:)
    blocks = Slack::Messages::Announcement.build(incident)
    post_message(
      channel_id: channel_id,
      text: "New incident: #{incident.identifier}",
      blocks: blocks
    )
  end

  def post_incident_update_message(channel_id:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
    blocks = Slack::Messages::StatusUpdate.build(
      incident,
      message: message,
      updated_by_platform_user_id: updated_by_platform_user_id,
      scope: :inline,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name,
      previous_type_name: previous_type_name
    )
    post_message(channel_id: channel_id, text: notification_text(incident), blocks: blocks)
  end

  def post_incident_update_announcement_thread(channel_id:, parent_message_id:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
    blocks = Slack::Messages::StatusUpdate.build(
      incident,
      message: message,
      updated_by_platform_user_id: updated_by_platform_user_id,
      scope: :announcement,
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name,
      previous_type_name: previous_type_name
    )
    post_threaded_message(channel_id: channel_id, parent_message_id: parent_message_id, text: notification_text(incident), blocks: blocks)
  end

  def post_incident_update_reminder(channel_id:, user_id:, incident:)
    blocks = Slack::Messages::StatusUpdate.update_reminder(incident)
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

  def open_timeline_modal(trigger_id:, incident:, offset: 0)
    view = build_timeline_view(incident, offset: offset)
    return unless view

    open_modal(trigger_id: trigger_id, view: view)
  end

  def push_timeline_modal(trigger_id:, incident:, offset: 0)
    view = build_timeline_view(incident, offset: offset)
    return unless view

    push_modal(trigger_id: trigger_id, view: view)
  end

  def update_timeline_modal(view_id:, incident:, offset: 0)
    view = build_timeline_view(incident, offset: offset)
    return unless view

    translate_errors do
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

  def post_resolution_message(channel_id:, incident:, resolved_by_platform_user_id:)
    blocks = Slack::Messages::Resolution.build(incident, resolved_by_platform_user_id: resolved_by_platform_user_id)
    post_message(channel_id: channel_id, text: "Incident resolved", blocks: blocks)
  end

  def post_resolution_announcement_thread(channel_id:, parent_message_id:, incident:, resolved_by_platform_user_id:)
    blocks = Slack::Messages::Resolution.announcement_thread(incident, resolved_by_platform_user_id: resolved_by_platform_user_id)
    post_threaded_message(channel_id: channel_id, parent_message_id: parent_message_id, text: "Incident resolved", blocks: blocks)
  end

  def post_related_link_message(channel_id:, source:, target:, linked_by_platform_user_id:)
    blocks = Slack::Messages::Link.related(source, target, linked_by_platform_user_id: linked_by_platform_user_id)
    post_message(channel_id: channel_id, text: "Incident linked", blocks: blocks)
  end

  def post_duplicate_source_message(channel_id:, source:, canonical:, linked_by_platform_user_id:)
    blocks = Slack::Messages::Link.duplicate_source(source, canonical, linked_by_platform_user_id: linked_by_platform_user_id)
    post_message(channel_id: channel_id, text: "Incident merged", blocks: blocks)
  end

  def post_duplicate_canonical_message(channel_id:, source:, canonical:, linked_by_platform_user_id:)
    blocks = Slack::Messages::Link.duplicate_canonical(source, canonical, linked_by_platform_user_id: linked_by_platform_user_id)
    post_message(channel_id: channel_id, text: "Duplicate merged in", blocks: blocks)
  end

  def post_reopen_message(channel_id:, incident:, reopened_by_platform_user_id:, reason: nil)
    blocks = Slack::Messages::Reopen.build(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reason: reason)
    post_message(channel_id: channel_id, text: "Incident reopened", blocks: blocks)
  end

  def post_reopen_announcement_thread(channel_id:, parent_message_id:, incident:, reopened_by_platform_user_id:, reason: nil)
    blocks = Slack::Messages::Reopen.announcement_thread(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reason: reason)
    post_threaded_message(channel_id: channel_id, parent_message_id: parent_message_id, text: "Incident reopened", blocks: blocks)
  end

  def post_escalation_message(channel_id:, incident:, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
    blocks = Slack::Messages::Escalation.build(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalated_to_platform_user_id: escalated_to_platform_user_id,
      reason: reason
    )
    post_message(channel_id: channel_id, text: "Incident escalated", blocks: blocks)
  end

  def post_escalation_announcement_thread(channel_id:, parent_message_id:, incident:, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
    blocks = Slack::Messages::Escalation.build(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalated_to_platform_user_id: escalated_to_platform_user_id,
      reason: reason
    )
    post_threaded_message(channel_id: channel_id, parent_message_id: parent_message_id, text: "Incident escalated", blocks: blocks)
  end

  def post_escalation_direct_message(user_id:, incident:, escalated_by_platform_user_id:, escalation_event_id:, reason: nil)
    blocks = Slack::Messages::Escalation.direct_message(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalation_event_id: escalation_event_id,
      reason: reason
    )
    post_message(channel_id: user_id, text: "Incident escalated to you", blocks: blocks)
  end

  def post_escalation_acknowledged_message(channel_id:, incident:, acknowledged_by_platform_user_id:, escalated_to_platform_user_id:)
    blocks = Slack::Messages::Escalation.acknowledged(
      incident,
      acknowledged_by_platform_user_id: acknowledged_by_platform_user_id,
      escalated_to_platform_user_id: escalated_to_platform_user_id
    )
    post_message(channel_id: channel_id, text: "Escalation acknowledged", blocks: blocks)
  end

  def mark_escalation_dm_acknowledged(channel_id:, message_id:, original_blocks:)
    blocks = Slack::Messages::Escalation.dm_after_acknowledgment(original_blocks)
    update_message(
      channel_id: channel_id,
      message_id: message_id,
      text: "Escalation acknowledged",
      blocks: blocks
    )
  end

  def post_escalation_nudge_direct_message(user_id:, incident:, escalated_by_platform_user_id:, escalation_event_id:, reason: nil)
    blocks = Slack::Messages::Escalation.direct_message(
      incident,
      escalated_by_platform_user_id: escalated_by_platform_user_id,
      escalation_event_id: escalation_event_id,
      reason: reason,
      variant: :nudge
    )
    post_message(channel_id: user_id, text: "Reminder to acknowledge escalation", blocks: blocks)
  end

  def post_action_message(channel_id:, action:)
    type_label = Slack::Messages::Action.label_for(action)
    blocks = Slack::Messages::Action.created(action)
    post_message(channel_id: channel_id, text: "New #{type_label} added", blocks: blocks)
  end

  def update_action_picked_up(channel_id:, message_id:, action:)
    blocks = Slack::Messages::Action.picked_up(action)
    type_label = Slack::Messages::Action.label_for(action)
    update_message(channel_id: channel_id, message_id: message_id, text: "#{type_label.capitalize} updated", blocks: blocks)
  end

  def update_action_completed(channel_id:, message_id:, action:)
    blocks = Slack::Messages::Action.completed(action)
    type_label = Slack::Messages::Action.label_for(action)
    update_message(channel_id: channel_id, message_id: message_id, text: "#{type_label.capitalize} updated", blocks: blocks)
  end

  def post_runbook_message(channel_id:, incident_runbook:)
    blocks = Slack::Messages::Runbook.attached(incident_runbook)
    post_message(channel_id: channel_id, text: "Runbook attached: #{incident_runbook.runbook.name}", blocks: blocks)
  end

  def update_runbook_message(channel_id:, message_id:, incident_runbook:)
    blocks = Slack::Messages::Runbook.attached(incident_runbook)
    update_message(channel_id: channel_id, message_id: message_id, text: "Runbook: #{incident_runbook.runbook.name}", blocks: blocks)
  end

  def post_action_handed_over(channel_id:, action:, reassigned_by:)
    post_handover(channel_id, action, Slack::Messages::Action.handed_over(action, reassigned_by))
  end

  def post_action_handover_notice(channel_id:, action:, reassigned_by:, link: nil)
    post_handover(channel_id, action, Slack::Messages::Action.handover_notice(action, reassigned_by, link: link))
  end

  def post_action_completed(channel_id:, action:, completed_by:, link: nil)
    post_message(
      channel_id: channel_id,
      text: "#{Slack::Messages::Action.label_for(action).capitalize} completed: #{action.description}",
      blocks: Slack::Messages::Action.completed_notice(action, completed_by, link: link)
    )
  end

  def post_handover(channel_id, action, blocks)
    post_message(
      channel_id: channel_id,
      text: "#{action.assignee&.display_name} now has this #{Slack::Messages::Action.label_for(action)}: #{action.description}",
      blocks: blocks
    )
  end

  def post_shoutout_message(channel_id:, incident:, from_user_id:, recipient_user_id:, message:)
    blocks = Slack::Messages::Shoutout.build(
      incident,
      from_user_id: from_user_id,
      recipient_user_id: recipient_user_id,
      message: message
    )
    post_message(channel_id: channel_id, text: ":heart_on_fire: Shoutout in #{incident.identifier}", blocks: blocks)
  end

  def post_shoutout_from_reaction_prompt(channel_id:, user_id:, incident_id:)
    blocks = Slack::Messages::Shoutout.from_reaction(incident_id)
    post_ephemeral(
      channel_id: channel_id,
      user_id: user_id,
      text: "Give a shoutout?",
      blocks: blocks
    )
  end

  def post_action_from_reaction_prompt(channel_id:, user_id:, action_type:, message_text:, incident_id:, source_message_link:)
    blocks = Slack::Messages::Action.from_reaction(
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

  def post_ai_response(channel_id:, incident:, answer:)
    blocks = Slack::Messages::AiResponse.build(incident: incident, answer: answer)
    post_message(channel_id: channel_id, text: answer, blocks: blocks)
  end

  def post_ai_response_threaded(channel_id:, parent_message_id:, incident:, answer:)
    blocks = Slack::Messages::AiResponse.build(incident: incident, answer: answer)
    post_threaded_message(channel_id: channel_id, parent_message_id: parent_message_id, text: answer, blocks: blocks)
  end

  def post_postmortem_message(channel_id:, incident:, postmortem:)
    blocks = Slack::Messages::Postmortem.build(incident, postmortem)
    post_message(
      channel_id: channel_id,
      text: "Postmortem generated for #{incident.identifier}",
      blocks: blocks
    )
  end

  def build_timeline_view(incident, offset: 0)
    total_events = incident.incident_events.count
    # Events can be written while a modal sits open, so a stale offset is
    # clamped back onto the timeline rather than rendering an empty window.
    offset = offset.to_i.clamp(0, [ total_events - 1, 0 ].max)
    events = incident.incident_events.includes(:eventable).recent.offset(offset).limit(TIMELINE_PAGE_SIZE).reverse
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

    if total_events > events.size
      newest_shown = total_events - offset
      oldest_shown = newest_shown - events.size + 1

      blocks << { type: "actions", elements: timeline_pager(incident, offset, total_events) }
      blocks << {
        type: "context",
        elements: [ { type: "mrkdwn", text: "Showing events #{oldest_shown} to #{newest_shown} of #{total_events}" } ]
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

  # Push notifications and the channel-list preview show this, never the
  # blocks, so a cancellation must not announce itself as an update.
  def notification_text(incident)
    incident.canceled? ? "Incident canceled" : "Incident updated"
  end

  def timeline_pager(incident, offset, total_events)
    elements = []
    if offset + TIMELINE_PAGE_SIZE < total_events
      elements << timeline_page_button("Older", incident.id, offset + TIMELINE_PAGE_SIZE)
    end
    if offset.positive?
      elements << timeline_page_button("Newer", incident.id, [ offset - TIMELINE_PAGE_SIZE, 0 ].max)
    end

    url = Slack::DashboardUrl.incident(incident)
    if url
      elements << { type: "button", text: { type: "plain_text", text: "View full timeline", emoji: true }, url: url }
    end

    elements
  end

  def timeline_page_button(label, incident_id, offset)
    {
      type: "button",
      text: { type: "plain_text", text: label, emoji: true },
      action_id: Identifiers::TIMELINE_PAGE,
      value: { incident_id: incident_id, offset: offset }.to_json
    }
  end
end
