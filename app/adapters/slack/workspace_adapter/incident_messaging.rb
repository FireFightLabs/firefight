module Slack::WorkspaceAdapter::IncidentMessaging
  extend ActiveSupport::Concern

  # Two blocks per event under Slack's 100-block modal ceiling, with room for
  # the header, divider and pager.
  TIMELINE_PAGE_SIZE = 45

  def post_alert_message(channel_id:, alert:)
    blocks = Slack::Messages::Alert.build(alert)
    post_message(channel_id: channel_id, text: Slack::Mrkdwn.escape(alert.title), blocks: blocks)
  end

  MODAL_EMOJI = {
    PlatformAdapter::Modal::INCIDENT_CANCEL => Slack::Emoji::CANCELED, PlatformAdapter::Modal::INCIDENT_CLOSE => Slack::Emoji::RESOLVED,
    PlatformAdapter::Modal::ESCALATE => Slack::Emoji::ESCALATED, PlatformAdapter::Modal::REOPEN => Slack::Emoji::REOPENED,
    PlatformAdapter::Modal::SUMMARY => Slack::Emoji::SUMMARY
  }.freeze

  def post_modal_placeholder(channel_id:, user_id:, modal:, doing:)
    post_message(channel_id: channel_id, text: "#{MODAL_EMOJI[modal]} #{Slack::Mrkdwn.person(user_id, nil)} is #{doing}...".lstrip, blocks: nil)
  end

  def post_summary_updated(channel_id:, updated_by_platform_user_id:)
    post_message(channel_id: channel_id, text: "#{Slack::Emoji::SUMMARY} Summary updated by #{Slack::Mrkdwn.person(updated_by_platform_user_id, nil)}", blocks: nil)
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
      text: Slack::Mrkdwn.escape(Slack::Messages::IncidentDetail.title_for(incident)),
      blocks: blocks
    )
  end

  def update_incident_announcement(channel_id:, message_id:, incident:)
    with_rich_blocks do |rich|
      update_message(channel_id: channel_id, message_id: message_id, text: announcement_text(incident),
                     blocks: Slack::Messages::Announcement.build(incident, rich: rich))
    end
  end

  def post_role_announcement(channel_id:, changes:)
    post_message(
      channel_id: channel_id,
      text: "Incident roles updated: #{Slack::Messages::RoleAssignment.summary_text(changes)}",
      blocks: Slack::Messages::RoleAssignment.announcement(changes)
    )
  end

  def post_lead_announcement(channel_id:, lead_platform_user_id:, lead_name: nil)
    blocks = Slack::Messages::LeadAssignment.announcement(lead_platform_user_id: lead_platform_user_id, lead_name: lead_name)
    post_message(
      channel_id: channel_id,
      text: "#{Slack::Mrkdwn.person(lead_platform_user_id, lead_name)} is now the Incident Lead",
      blocks: blocks
    )
  end

  def post_lead_invite_failed(channel_id:, lead_platform_user_id:, lead_name: nil)
    text = Slack::Messages::LeadAssignment.invite_failed(lead_platform_user_id: lead_platform_user_id, lead_name: lead_name)
    post_message(channel_id: channel_id, text: text, blocks: nil)
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
      text: Slack::Mrkdwn.escape(Slack::Messages::IncidentDetail.title_for(incident)),
      blocks: blocks
    )
  end

  def post_first_incident_walkthrough(channel_id:, incident:, step:)
    post_message(
      channel_id: channel_id,
      text: Slack::Messages::FirstIncidentWalkthrough.fallback_text(step),
      blocks: Slack::Messages::FirstIncidentWalkthrough.build(incident, step: step)
    )
  end

  def post_incident_announcement(channel_id:, incident:)
    with_rich_blocks do |rich|
      post_message(channel_id: channel_id, text: announcement_text(incident), blocks: Slack::Messages::Announcement.build(incident, rich: rich))
    end
  end

  def post_incident_update_message(channel_id:, incident:, message:, updated_by_platform_user_id:, updated_by_name: nil, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
    with_rich_blocks do |rich|
      blocks = Slack::Messages::StatusUpdate.build(
        incident,
        message: message,
        updated_by_platform_user_id: updated_by_platform_user_id,
        updated_by_name: updated_by_name,
        scope: :inline,
        rich: rich,
        previous_status_name: previous_status_name,
        previous_severity_name: previous_severity_name,
        previous_type_name: previous_type_name
      )
      post_message(channel_id: channel_id, text: notification_text(incident), blocks: blocks)
    end
  end

  def post_incident_update_announcement_thread(channel_id:, parent_message_id:, incident:, message:, updated_by_platform_user_id:, updated_by_name: nil, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil, subscriber_user_ids: [])
    reply = lambda do |rich|
      Slack::Messages::StatusUpdate.build(
        incident,
        message: message,
        updated_by_platform_user_id: updated_by_platform_user_id,
        updated_by_name: updated_by_name,
        scope: :announcement,
        rich: rich,
        previous_status_name: previous_status_name,
        previous_severity_name: previous_severity_name,
        previous_type_name: previous_type_name
      )
    end
    headline = Slack::Messages::StatusUpdate.digest_line(incident, updated_by_platform_user_id, updated_by_name,
                                                         previous_status_name, previous_severity_name, previous_type_name)
    digest = { headline: headline, body: message, icon: incident.canceled? ? Slack::Emoji::CANCELED : Slack::Emoji::UPDATED }
    reply_and_notify_subscribers(channel_id, parent_message_id, subscriber_user_ids, incident: incident, text: notification_text(incident),
                                 reply: reply, digest: digest)
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
    lead = incident.lead ? Slack::Mrkdwn.mention(incident.lead) : "Unassigned"
    channel = if incident.channel_id.present?
      "<##{incident.channel_id}>"
    elsif incident.is_private?
      "Private channel"
    else
      "No channel"
    end

    [
      "> *#{incident.identifier}* #{incident.name || 'Untitled Incident'}",
      "> #{[ incident.incident_severity.name, incident.incident_status.name, "Lead: #{lead}", channel ].join(Slack::Messages::Formatting::SEPARATOR)}"
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

  def post_resolution_message(channel_id:, incident:, resolved_by_platform_user_id:, resolved_by_name: nil)
    with_rich_blocks do |rich|
      blocks = Slack::Messages::Resolution.build(incident, resolved_by_platform_user_id: resolved_by_platform_user_id, resolved_by_name: resolved_by_name, rich: rich)
      post_message(channel_id: channel_id, text: "Incident resolved", blocks: blocks)
    end
  end

  def post_resolution_announcement_thread(channel_id:, parent_message_id:, incident:, resolved_by_platform_user_id:, resolved_by_name: nil, subscriber_user_ids: [])
    reply = ->(rich) { Slack::Messages::Resolution.announcement_thread(incident, resolved_by_platform_user_id: resolved_by_platform_user_id, resolved_by_name: resolved_by_name, rich: rich) }
    digest = { headline: Slack::Messages::Resolution.headline(incident, resolved_by_platform_user_id, resolved_by_name), body: incident.summary,
               icon: Slack::Emoji::RESOLVED }
    reply_and_notify_subscribers(channel_id, parent_message_id, subscriber_user_ids, incident: incident, text: "Incident resolved",
                                 reply: reply, digest: digest)
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

  def post_reopen_message(channel_id:, incident:, reopened_by_platform_user_id:, reopened_by_name: nil, reason: nil)
    with_rich_blocks do |rich|
      blocks = Slack::Messages::Reopen.build(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reopened_by_name: reopened_by_name, reason: reason, rich: rich)
      post_message(channel_id: channel_id, text: "Incident reopened", blocks: blocks)
    end
  end

  def post_reopen_announcement_thread(channel_id:, parent_message_id:, incident:, reopened_by_platform_user_id:, reopened_by_name: nil, reason: nil, subscriber_user_ids: [])
    reply = lambda do |rich|
      Slack::Messages::Reopen.announcement_thread(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reopened_by_name: reopened_by_name,
                                                            reason: reason, rich: rich)
    end
    digest = { headline: Slack::Messages::Reopen.headline(reopened_by_platform_user_id, reopened_by_name), body: reason, icon: Slack::Emoji::REOPENED }
    reply_and_notify_subscribers(channel_id, parent_message_id, subscriber_user_ids, incident: incident, text: "Incident reopened",
                                 reply: reply, digest: digest)
  end

  def post_subscription_notice(channel_id:, user_id:, incident:, state:)
    post_ephemeral(
      channel_id: channel_id,
      user_id: user_id,
      text: incident.subscription_notice(state),
      blocks: Slack::Messages::Subscription.notice(incident, state)
    )
  end

  def post_escalation_message(channel_id:, incident:, escalated_by:, escalated_to:, reason: nil)
    with_rich_blocks do |rich|
      blocks = Slack::Messages::Escalation.build(incident, escalated_by: escalated_by, escalated_to: escalated_to, reason: reason, rich: rich)
      post_message(channel_id: channel_id, text: "Incident escalated", blocks: blocks)
    end
  end

  def post_escalation_announcement_thread(channel_id:, parent_message_id:, incident:, escalated_by:, escalated_to:, reason: nil, subscriber_user_ids: [])
    reply = ->(rich) { Slack::Messages::Escalation.build(incident, escalated_by: escalated_by, escalated_to: escalated_to, reason: reason, rich: rich) }
    digest = { headline: Slack::Messages::Escalation.headline(escalated_by, escalated_to), body: reason, icon: Slack::Emoji::ESCALATED }
    reply_and_notify_subscribers(channel_id, parent_message_id, subscriber_user_ids, incident: incident, text: "Incident escalated",
                                 reply: reply, digest: digest)
  end

  def post_escalation_direct_message(user_id:, incident:, escalated_by:, escalation_event_id:, reason: nil)
    blocks = Slack::Messages::Escalation.direct_message(
      incident, escalated_by: escalated_by, escalation_event_id: escalation_event_id, reason: reason
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

  def post_escalation_nudge_direct_message(user_id:, incident:, escalated_by:, escalation_event_id:, reason: nil)
    blocks = Slack::Messages::Escalation.direct_message(
      incident, escalated_by: escalated_by, escalation_event_id: escalation_event_id,
      reason: reason, variant: :nudge
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

  def refresh_action_message(channel_id:, message_id:, action:)
    blocks = Slack::Messages::Action.current(action)
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
      text: "#{action.assignee&.actor_display_name} now has this #{Slack::Messages::Action.label_for(action)}: #{action.description}",
      blocks: blocks
    )
  end

  def post_invite_unresolved(channel_id:, user_id:, targets:)
    post_ephemeral(channel_id: channel_id, user_id: user_id, text: Slack::Messages::Invite.unresolved(targets))
  end

  def post_invite_summary(channel_id:, user_id:, result:)
    post_ephemeral(channel_id: channel_id, user_id: user_id, text: Slack::Messages::Invite.summary(result))
  end

  def post_shoutout_message(channel_id:, incident:, from:, to:, message:)
    blocks = Slack::Messages::Shoutout.build(incident, from: from, to: to, message: message)
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

  def post_action_from_reaction_prompt(channel_id:, user_id:, action_type:, message_id:, message_text:, incident_id:, source_message_link:)
    blocks = Slack::Messages::Action.from_reaction(
      action_type, message_text, incident_id, source_message_link, channel_id: channel_id, message_id: message_id
    )
    type_label = action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
    post_ephemeral(
      channel_id: channel_id,
      user_id: user_id,
      text: "Create #{type_label} from this message?",
      blocks: blocks
    )
  end

  # AiResponse converts markdown to mrkdwn on the way out, so the model only
  # has to avoid headers and single-asterisk italics, which collide with bold.
  AI_OUTPUT_STYLE = <<~STYLE
    Use Slack mrkdwn formatting: *bold*, _italic_, bullet points, and `code` where appropriate.
    Do not use markdown headers (#). Use *bold text* instead.
  STYLE

  # Slack renders streamed text as markdown, not mrkdwn, so bold needs two asterisks.
  AI_STREAM_OUTPUT_STYLE = <<~STYLE
    Use markdown: **bold**, _italic_, bullet points, and `code` where appropriate.
    Do not use markdown headers (#). Use **bold text** instead.
    Write a link as [what it is](https://the.full/address), such as [PR #856](https://github.com/acme/app/pull/856).
  STYLE

  # Slack allows about one append a second. Markdown cut across two appends, a link among it, can show as its raw
  # characters, so an append never cuts a link, bold or code in two (Conversation::ChunkBuffer).
  AGENT_STREAM_CADENCE = { interval: 1.second, max_chars: 256, whole_markup: true }.freeze

  def ai_output_style
    AI_OUTPUT_STYLE
  end

  def ai_stream_output_style
    AI_STREAM_OUTPUT_STYLE
  end

  def agent_stream_cadence
    AGENT_STREAM_CADENCE
  end

  # Every few seconds is well inside what Slack allows for a stream and for editing a message, and keeps up with a
  # person reading along.
  AGENT_STEP_UPDATE_INTERVAL = 5

  def agent_step_update_interval
    AGENT_STEP_UPDATE_INTERVAL
  end

  # An answer longer than one message holds runs on into the next, so it is never cut.
  def post_ai_response(channel_id:, incident:, answer:)
    parts = Slack::Messages::Formatting.message_parts(Slack::Messages::AiResponse.build(incident: incident, answer: answer))
    fallback = "#{incident.identifier}: #{answer.to_s.squish.truncate(200)}"
    parts.map { |blocks| post_message(channel_id: channel_id, text: fallback, blocks: blocks) }.first
  end

  STEP_STATUSES = { running: "in_progress", done: "complete" }.freeze
  # A finished step that failed is an error, and one whose provider found nothing, or that one of Firefight's own rules
  # refused, is complete, an answer rather than a breakage. Each says how it went in a word under its title.
  STEP_ERROR = "error".freeze
  STEP_OUTCOME_WORDS = {
    Chat::StepOutcome::KIND_FAILED => "Failed", Chat::StepOutcome::KIND_NOT_FOUND => "Not found", Chat::StepOutcome::KIND_REFUSED => "Refused",
    Chat::StepOutcome::KIND_STOPPED => "Stopped"
  }.freeze

  # A bot posts to any public channel, but not to a private one it is not in. Posting to a person opens their DM with it.
  def post_investigation_started(channel_id:, incident:, started_by:, progress:, question: nil, fallback_user_id: nil)
    text = Slack::Messages::InvestigationRun.started_text(incident: incident, question: question)
    with_rich_blocks do |rich|
      blocks = Slack::Messages::InvestigationRun.checklist(progress: progress, incident: incident, question: question, started_by: started_by, rich: rich)
      begin
        post_message(channel_id: channel_id, text: text, blocks: blocks)
      rescue AdapterError::NotInChannel, AdapterError::NotFound
        raise if fallback_user_id.blank?

        post_message(channel_id: fallback_user_id, text: text, blocks: blocks)
      end
    end
  end

  def update_investigation_progress(channel_id:, message_id:, incident:, started_by:, progress:, question: nil)
    text = Slack::Messages::InvestigationRun.checklist_title(progress, incident, question)
    with_rich_blocks do |rich|
      blocks = Slack::Messages::InvestigationRun.checklist(progress: progress, incident: incident, question: question, started_by: started_by, rich: rich)
      update_message(channel_id: channel_id, message_id: message_id, text: text, blocks: blocks)
    end
  end

  # A workspace without the agent features still gets the answer, just posted in one go at the end.
  def start_agent_answer(channel_id:, thread_id:, user_id:)
    translate_errors do
      Slack::Client.set_agent_session_status(
        workspace: @workspace, channel: channel_id, thread_ts: thread_id, status: "processing"
      )
      stream = Slack::Client.start_stream(
        workspace: @workspace, channel: channel_id, thread_ts: thread_id,
        recipient_user_id: user_id, recipient_team_id: @workspace.platform_id
      )
      { answer_id: stream[:ts] }
    end
  rescue AdapterError => error
    Rails.logger.info("slack.agent_answer.unavailable error=#{error.class.name} message=#{error.message}")
    { answer_id: nil }
  end

  # Slack cuts a task's details at 256 characters.
  STEP_DETAILS_LIMIT = 256

  def report_agent_step(channel_id:, answer_id:, key:, title:, status:, outcome: nil, details: nil)
    return { success: true } if answer_id.blank?

    shown = outcome == Chat::StepOutcome::KIND_FAILED ? STEP_ERROR : STEP_STATUSES.fetch(status)
    task = { type: "task_update", id: key, title: title, status: shown, details: details&.truncate(STEP_DETAILS_LIMIT),
             output: STEP_OUTCOME_WORDS[outcome] }.compact
    translate_errors do
      Slack::Client.append_stream(workspace: @workspace, channel: channel_id, ts: answer_id, chunks: [ task ])
      { success: true }
    end
  rescue AdapterError => error
    Rails.logger.info("slack.agent_step.dropped error=#{error.class.name} message=#{error.message}")
    { success: true }
  end

  # A stopped or timed out stream refuses appends, so the caller falls back to posting the whole answer.
  # Slack reads streamed text as markdown, which shows nothing of its own <url|label>, so such a link goes as markdown's.
  def append_agent_text(channel_id:, answer_id:, text:)
    return { streaming: false } if answer_id.blank?

    translate_errors do
      Slack::Client.append_stream(
        workspace: @workspace, channel: channel_id, ts: answer_id,
        chunks: [ { type: "markdown_text", text: Slack::Messages::Formatting.mrkdwn_links_to_markdown(text) } ]
      )
      { streaming: true }
    end
  rescue AdapterError => error
    Rails.logger.info("slack.agent_text.dropped error=#{error.class.name} message=#{error.message}")
    { streaming: false }
  end

  # A question asked in Slack is posted back as Slack shows it, so a mention or a broadcast in it never notifies again.
  def post_investigation_carried_over(channel_id:, finding:)
    run = finding.investigation
    question = run.question
    question = messages_as_text(texts: [ question ])[question] if question.present? && run.question_in_platform_markup?
    posted = post_message(
      channel_id: channel_id, text: Slack::Messages::InvestigationRun.answer_text(finding),
      blocks: Slack::Messages::InvestigationRun.carried_over(finding: finding, question: question)
    )
    post_answer_detail(channel_id, posted[:message_id], finding)
    posted
  end

  # The working state ends with the steps the thread already shows. The short answer then goes to the thread and the
  # channel, and the full answer follows it in the thread.
  def post_investigation_answer(channel_id:, thread_id:, answer_id:, finding:)
    end_agent_steps(channel_id: channel_id, thread_id: thread_id, answer_id: answer_id)
    posted = post_threaded_message(
      channel_id: channel_id, parent_message_id: thread_id, text: Slack::Messages::InvestigationRun.answer_text(finding),
      blocks: Slack::Messages::InvestigationRun.answer(finding: finding), broadcast: true
    )
    post_answer_detail(channel_id, thread_id, finding)
    posted
  end

  def post_investigation_stopped(channel_id:, thread_id:, answer_id:, reason:, where_it_stopped: nil, rerun: nil, rerun_question: nil,
                                 investigation: nil)
    finish_agent_answer(
      channel_id: channel_id, thread_id: thread_id, answer_id: answer_id,
      text: [ "Stopped without an answer. #{reason}.", where_it_stopped ].compact.join("\n\n"),
      blocks: Slack::Messages::InvestigationRun.stopped(
        reason: reason, where_it_stopped: where_it_stopped, rerun: rerun, rerun_question: rerun_question, investigation: investigation
      )
    )
  end

  # The stream was never stopped, so it is stopped now with the ending as its last words.
  def end_interrupted_answer(channel_id:, message_id:, shown:, ending:)
    translate_errors do
      if shown
        Slack::Client.stop_stream(workspace: @workspace, channel: channel_id, ts: message_id, markdown_text: "\n\n#{ending}")
      else
        Slack::Client.delete_message(workspace: @workspace, channel: channel_id, ts: message_id)
      end
      { success: true }
    end
  end

  def ask_agent_confirmation(channel_id:, thread_id:, answer_id:, conversation_id:, confirmations:)
    with_rich_blocks do |rich|
      finish_agent_answer(
        channel_id: channel_id, thread_id: thread_id, answer_id: answer_id,
        text: Slack::Messages::AgentConfirmation.fallback(confirmations),
        blocks: Slack::Messages::AgentConfirmation.build(conversation_id: conversation_id, confirmations: confirmations, rich: rich)
      )
    end
  end

  def update_agent_confirmation(channel_id:, message_id:, conversation_id:, confirmations:)
    with_rich_blocks do |rich|
      update_message(
        channel_id: channel_id, message_id: message_id,
        text: Slack::Messages::AgentConfirmation.fallback(confirmations),
        blocks: Slack::Messages::AgentConfirmation.build(conversation_id: conversation_id, confirmations: confirmations, rich: rich)
      )
    end
    { success: true }
  end

  # A trigger opens one view, so the modal is never sent a second time the way a message is. A refused alert block is
  # remembered instead, so the next Details opens plainly.
  def open_agent_confirmation_details(trigger_id:, confirmation:)
    rich = rich_blocks?
    open_modal(trigger_id: trigger_id, view: Slack::Modals::AgentConfirmationDetails.build(confirmation, rich: rich))
  rescue AdapterError::Unrenderable => error
    raise unless rich

    Rails.logger.info({ event: "slack.rich_blocks_refused", workspace_id: @workspace.id, error: error.message }.to_json)
    rich_blocks_refused!
    { success: false }
  end

  def update_investigation_answer(channel_id:, message_id:, finding:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::InvestigationRun.answer_text(finding),
                   blocks: Slack::Messages::InvestigationRun.answer(finding: finding))
    { success: true }
  end

  def post_undo_plan(channel_id:, thread_id:, plan:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: "How to undo it: #{plan.summary}", blocks: Slack::Messages::InvestigationRun.undo(plan: plan))
  end

  def post_fix_progress(channel_id:, thread_id:, plan:)
    with_rich_blocks do |rich|
      post_threaded_message(channel_id: channel_id, parent_message_id: thread_id, broadcast: true,
                            text: Slack::Messages::FixProgress.fallback(plan), blocks: Slack::Messages::FixProgress.build(plan, rich: rich))
    end
  end

  def update_fix_progress(channel_id:, message_id:, plan:)
    with_rich_blocks do |rich|
      update_message(channel_id: channel_id, message_id: message_id,
                     text: Slack::Messages::FixProgress.fallback(plan), blocks: Slack::Messages::FixProgress.build(plan, rich: rich))
    end
    { success: true }
  end

  def post_unattended_note(channel_id:, thread_id:, note:)
    text = Slack::Messages::OnCall.unattended_fallback(note)
    blocks = Slack::Messages::OnCall.unattended(note)
    return post_threaded_message(channel_id: channel_id, parent_message_id: thread_id, text: text, blocks: blocks) if thread_id

    post_message(channel_id: channel_id, text: text, blocks: blocks)
  end

  def post_alert_run_held(channel_id:, incident:, reason:, rerun:)
    post_message(channel_id: channel_id, text: reason, blocks: Slack::Messages::OnCall.held(incident: incident, reason: reason, rerun: rerun))
  end

  def post_learned_memories(channel_id:, thread_id:, post:)
    translate_errors do
      result = Slack::Client.post_message(
        workspace: @workspace, channel: channel_id, thread_ts: thread_id,
        text: Slack::Messages::LearnedMemories.fallback(post), blocks: Slack::Messages::LearnedMemories.build(post)
      )
      { message_id: result[:ts], channel_id: result[:channel] || channel_id }
    end
  end

  def post_learned_memories_to_user(user_id:, post:)
    post_message(channel_id: user_id, text: Slack::Messages::LearnedMemories.fallback(post), blocks: Slack::Messages::LearnedMemories.build(post))
  end

  def update_learned_memories(channel_id:, message_id:, post:)
    update_message(channel_id: channel_id, message_id: message_id,
                   text: Slack::Messages::LearnedMemories.fallback(post), blocks: Slack::Messages::LearnedMemories.build(post))
    { success: true }
  end

  def post_handbook_proposal(channel_id:, thread_id:, proposal:)
    translate_errors do
      result = Slack::Client.post_message(
        workspace: @workspace, channel: channel_id, thread_ts: thread_id,
        text: Slack::Messages::HandbookProposal.fallback(proposal), blocks: Slack::Messages::HandbookProposal.build(proposal)
      )
      { message_id: result[:ts], channel_id: result[:channel] || channel_id }
    end
  end

  def update_handbook_proposal(channel_id:, message_id:, proposal:)
    update_message(channel_id: channel_id, message_id: message_id,
                   text: Slack::Messages::HandbookProposal.fallback(proposal), blocks: Slack::Messages::HandbookProposal.build(proposal))
    { success: true }
  end

  def post_skill_proposal(channel_id:, thread_id:, proposal:)
    translate_errors do
      result = Slack::Client.post_message(
        workspace: @workspace, channel: channel_id, thread_ts: thread_id,
        text: Slack::Messages::SkillProposal.fallback(proposal), blocks: Slack::Messages::SkillProposal.build(proposal)
      )
      { message_id: result[:ts], channel_id: result[:channel] || channel_id }
    end
  end

  def update_skill_proposal(channel_id:, message_id:, proposal:)
    update_message(channel_id: channel_id, message_id: message_id,
                   text: Slack::Messages::SkillProposal.fallback(proposal), blocks: Slack::Messages::SkillProposal.build(proposal))
    { success: true }
  end

  def post_held_call(channel_id:, thread_id:, held_call:)
    with_rich_blocks do |rich|
      post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                            text: Slack::Messages::HeldCall.fallback(held_call), blocks: Slack::Messages::HeldCall.build(held_call, rich: rich))
    end
  end

  def post_held_call_to_user(user_id:, held_call:)
    with_rich_blocks do |rich|
      post_message(channel_id: user_id, text: Slack::Messages::HeldCall.fallback(held_call),
                   blocks: Slack::Messages::HeldCall.build(held_call, direct: true, rich: rich))
    end
  end

  def update_held_call(channel_id:, message_id:, held_call:, direct: false)
    with_rich_blocks do |rich|
      update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::HeldCall.fallback(held_call),
                     blocks: Slack::Messages::HeldCall.build(held_call, direct: direct, rich: rich))
    end
    { success: true }
  end

  def open_held_call_details(trigger_id:, held_call:)
    open_modal(trigger_id: trigger_id, view: Slack::Modals::HeldCallDetails.build(held_call))
  end

  def post_watch_update(channel_id:, thread_id:, update:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::WatchUpdate.fallback(update), blocks: Slack::Messages::WatchUpdate.build(update))
  end

  def post_watch_update_to_user(user_id:, update:, conversation_id: nil)
    post_message(channel_id: user_id, text: Slack::Messages::WatchUpdate.fallback(update),
                 blocks: Slack::Messages::WatchUpdate.build(update, direct: true, conversation_id: conversation_id))
  end

  def update_watch_update(channel_id:, message_id:, update:, direct: false, conversation_id: nil)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::WatchUpdate.fallback(update),
                   blocks: Slack::Messages::WatchUpdate.build(update, direct: direct, conversation_id: conversation_id))
    { success: true }
  end

  def post_chat_plan(channel_id:, thread_id:, plan:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::ChatPlan.fallback(plan), blocks: Slack::Messages::ChatPlan.build(plan))
  end

  def post_chat_plan_to_user(user_id:, plan:, conversation_id: nil)
    post_message(channel_id: user_id, text: Slack::Messages::ChatPlan.fallback(plan),
                 blocks: Slack::Messages::ChatPlan.build(plan, direct: true, conversation_id: conversation_id))
  end

  def update_chat_plan(channel_id:, message_id:, plan:, direct: false, conversation_id: nil)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::ChatPlan.fallback(plan),
                   blocks: Slack::Messages::ChatPlan.build(plan, direct: direct, conversation_id: conversation_id))
    { success: true }
  end

  def post_mitigation_notice(channel_id:, thread_id:, notice:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::MitigationNotice.fallback(notice), blocks: Slack::Messages::MitigationNotice.build(notice))
  end

  def post_mitigation_notice_to_user(user_id:, notice:)
    post_message(channel_id: user_id, text: Slack::Messages::MitigationNotice.fallback(notice),
                 blocks: Slack::Messages::MitigationNotice.build(notice, direct: true))
  end

  def update_mitigation_notice(channel_id:, message_id:, notice:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::MitigationNotice.fallback(notice),
                   blocks: Slack::Messages::MitigationNotice.build(notice, direct: direct_conversation?(channel_id: channel_id)))
    { success: true }
  end

  def post_owner_ask(user_id:, ask:)
    post_message(channel_id: user_id, text: Slack::Messages::OwnerAsk.fallback(ask), blocks: Slack::Messages::OwnerAsk.build(ask))
  end

  def update_owner_ask(channel_id:, message_id:, ask:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::OwnerAsk.fallback(ask), blocks: Slack::Messages::OwnerAsk.build(ask))
    { success: true }
  end

  def post_monitoring_notice(channel_id:, notice:)
    post_message(channel_id: channel_id, text: Slack::Messages::MonitoringNotice.fallback(notice), blocks: Slack::Messages::MonitoringNotice.build(notice))
  end

  def post_pull_request_notice(channel_id:, thread_id:, notice:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::PullRequestNotice.fallback(notice), blocks: Slack::Messages::PullRequestNotice.build(notice))
  end

  def post_pull_request_notice_to_user(user_id:, notice:, conversation_id: nil)
    post_message(channel_id: user_id, text: Slack::Messages::PullRequestNotice.fallback(notice),
                 blocks: Slack::Messages::PullRequestNotice.build(notice, conversation_id: conversation_id))
  end

  def update_pull_request_notice(channel_id:, message_id:, notice:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::PullRequestNotice.fallback(notice),
                   blocks: Slack::Messages::PullRequestNotice.build(notice, conversation_id: (notice.conversation_id if direct_conversation?(channel_id: channel_id))))
    { success: true }
  end

  # Slack names a direct message channel with a D.
  def direct_conversation?(channel_id:) = channel_id.to_s.start_with?("D")

  def post_pack_refusal(channel_id:, thread_id:, refusal:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::PackRefusal.fallback(refusal), blocks: Slack::Messages::PackRefusal.build(refusal))
  end

  def update_pack_refusal(channel_id:, message_id:, refusal:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::PackRefusal.fallback(refusal),
                   blocks: Slack::Messages::PackRefusal.build(refusal))
    { success: true }
  end

  def post_secret_entry(channel_id:, thread_id:, entry:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::SecretEntry.fallback(entry), blocks: Slack::Messages::SecretEntry.build(entry))
  end

  def update_secret_entry(channel_id:, message_id:, entry:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::SecretEntry.fallback(entry),
                   blocks: Slack::Messages::SecretEntry.build(entry))
    { success: true }
  end

  def post_code_question(channel_id:, thread_id:, question:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::CodeQuestion.fallback(question), blocks: Slack::Messages::CodeQuestion.build(question))
  end

  def post_code_pause(channel_id:, thread_id:, pause:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::CodePause.fallback(pause), blocks: Slack::Messages::CodePause.build(pause))
  end

  def post_code_pause_to_user(user_id:, pause:)
    post_message(channel_id: user_id, text: Slack::Messages::CodePause.fallback(pause), blocks: Slack::Messages::CodePause.build(pause))
  end

  def update_code_pause(channel_id:, message_id:, pause:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::CodePause.fallback(pause),
                   blocks: Slack::Messages::CodePause.build(pause))
    { success: true }
  end

  def post_workflow_question(user_id:, question:)
    post_message(channel_id: user_id, text: Slack::Messages::WorkflowQuestion.fallback(question), blocks: Slack::Messages::WorkflowQuestion.build(question))
  end

  def post_workflow_question_in_channel(channel_id:, question:)
    post_message(channel_id: channel_id, text: Slack::Messages::WorkflowQuestion.fallback(question), blocks: Slack::Messages::WorkflowQuestion.build(question))
  end

  def update_workflow_question(channel_id:, message_id:, question:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::WorkflowQuestion.fallback(question),
                   blocks: Slack::Messages::WorkflowQuestion.build(question))
    { success: true }
  end

  def update_code_question(channel_id:, message_id:, question:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::CodeQuestion.fallback(question),
                   blocks: Slack::Messages::CodeQuestion.build(question))
    { success: true }
  end

  def post_pack_answer_to_user(user_id:, pack_request:)
    post_message(channel_id: user_id, text: Slack::Messages::PackAnswer.fallback(pack_request, direct: true),
                 blocks: Slack::Messages::PackAnswer.build(pack_request, direct: true))
  end

  def post_pack_answer(channel_id:, thread_id:, pack_request:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::PackAnswer.fallback(pack_request), blocks: Slack::Messages::PackAnswer.build(pack_request))
  end

  def post_pack_request_to_user(user_id:, pack_request:)
    post_message(channel_id: user_id, text: Slack::Messages::PackRequest.fallback(pack_request), blocks: Slack::Messages::PackRequest.build(pack_request))
  end

  def update_pack_request(channel_id:, message_id:, pack_request:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::PackRequest.fallback(pack_request),
                   blocks: Slack::Messages::PackRequest.build(pack_request))
    { success: true }
  end

  def post_fix_step_to_user(user_id:, step:)
    post_message(channel_id: user_id, text: Slack::Messages::FixProgress.step_news_fallback(step), blocks: Slack::Messages::FixProgress.step_news(step))
  end

  # Blocks after a stream render below the streamed text, so a reply the person already read gets none.
  def post_integration_card(channel_id:, thread_id:, card:)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id,
                          text: Slack::Messages::IntegrationCard.fallback(card), blocks: Slack::Messages::IntegrationCard.build(card))
  end

  def post_charts(channel_id:, thread_id:, charts:)
    translate_errors do
      charts.map { |chart| { message_id: post_chart(channel_id, thread_id, chart)[:ts], channel_id: channel_id } }
    end
  end

  def post_screenshots(channel_id:, thread_id:, screenshots:, left_out: 0)
    translate_errors do
      posted = screenshots.map { |shot| { message_id: post_screenshot(channel_id, thread_id, shot)[:ts], channel_id: channel_id } }
      if left_out.positive?
        Slack::Client.post_message(workspace: @workspace, channel: channel_id, thread_ts: thread_id,
                                   text: Slack::Messages::ScreenshotCaption.left_out(left_out))
      end
      posted
    end
  end

  # A streamed answer keeps the text the person already read, and the sources block goes at its bottom.
  # A reply longer than one message holds ends the answer with its first part and runs on in the thread, the sources
  # under the last part.
  def post_agent_reply(channel_id:, thread_id:, answer_id:, text:, streamed: false, sources: [])
    read = Slack::Messages::AgentSources.build(sources)
    return finish_agent_answer(channel_id: channel_id, thread_id: thread_id, answer_id: answer_id, text: text, blocks: read.presence) if streamed

    first, *rest = Slack::Messages::Formatting.message_parts(Slack::Messages::AgentReply.build(text: text))
    (rest.last || first).concat(read)
    result = finish_agent_answer(channel_id: channel_id, thread_id: thread_id, answer_id: answer_id, text: text, blocks: first)
    rest.each do |blocks|
      Slack::Client.post_message(workspace: @workspace, channel: channel_id, thread_ts: thread_id, text: blocks.first.dig(:text, :text).to_s, blocks: blocks)
    end
    result
  end

  def finish_agent_answer(channel_id:, thread_id:, answer_id:, text:, blocks:)
    result = if answer_id.present?
      Slack::Client.stop_stream(workspace: @workspace, channel: channel_id, ts: answer_id, blocks: blocks)
    else
      Slack::Client.post_message(workspace: @workspace, channel: channel_id, text: text, blocks: blocks, thread_ts: thread_id)
    end
    clear_agent_session(channel_id: channel_id, thread_id: thread_id)
    { message_id: result[:ts], channel_id: channel_id }
  end

  # Slack holds the spinner for an hour unless the session is set back to active.
  def clear_agent_session(channel_id:, thread_id:)
    Slack::Client.set_agent_session_status(
      workspace: @workspace, channel: channel_id, thread_ts: thread_id, status: "active"
    )
  rescue AdapterError => error
    Rails.logger.info("slack.agent_session.clear_failed error=#{error.class.name} message=#{error.message}")
  end

  def post_postmortem_generation_failed(channel_id:, user_id:, incident:, reason:, retrying:, note: nil)
    text = if note
      ":warning: Postmortem generation for #{incident.identifier} failed. #{note}"
    elsif retrying
      ":warning: Postmortem generation for #{incident.identifier} failed after retries (reason: #{reason}). Try again from the incident page or with `/ff #{Identifiers::SUBCOMMAND_POSTMORTEM}`."
    else
      ":warning: Postmortem generation for #{incident.identifier} failed (reason: #{reason}) and won't retry automatically. Try again from the incident page or with `/ff #{Identifiers::SUBCOMMAND_POSTMORTEM}`."
    end
    post_ephemeral(channel_id: channel_id, user_id: user_id, text: text)
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
    total_events = incident.incident_events.undismissed.count
    # Events can be written while the modal is open, so a stale offset is
    # clamped instead of rendering an empty page.
    offset = offset.to_i.clamp(0, [ total_events - 1, 0 ].max)
    events = IncidentEvent.with_update_history(
      incident.incident_events.undismissed.includes(:eventable).recent.offset(offset).limit(TIMELINE_PAGE_SIZE).reverse
    )
    return nil if events.empty?

    lead_text = incident.lead ? Slack::Mrkdwn.mention(incident.lead) : "Unassigned"
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

  # Where the workspace's Slack refused one of the newer blocks (plan, card), remembered on the workspace, so its messages
  # go as plain blocks without asking again until RETRY_RICH_BLOCKS_AFTER has passed, in case the workspace changed plans.
  # The key keeps the name it had when plan blocks were the only ones, so a refusal already remembered still counts.
  RICH_BLOCKS_REFUSED_AT = "plan_blocks_refused_at".freeze
  RETRY_RICH_BLOCKS_AFTER = 7.days

  # Yields whether to draw the newer blocks, and draws the same message plainly when Slack refuses them, so nothing is
  # lost to how it looks.
  def with_rich_blocks
    if rich_blocks?
      begin
        return yield(true)
      rescue AdapterError::Unrenderable => error
        Rails.logger.info({ event: "slack.rich_blocks_refused", workspace_id: @workspace.id, error: error.message }.to_json)
        rich_blocks_refused!
      end
    end
    yield(false)
  end

  def rich_blocks?
    refused = @workspace.platform_data.to_h[RICH_BLOCKS_REFUSED_AT]
    refused.blank? || Time.zone.parse(refused.to_s) < RETRY_RICH_BLOCKS_AFTER.ago
  end

  def rich_blocks_refused! = @workspace.remember_platform_data!(RICH_BLOCKS_REFUSED_AT, Time.current.iso8601)

  # Stops the stream that showed the run's steps in its thread, keeping them, and clears the working state. A stream that
  # already ended is left as it was, since the answer follows it either way.
  def end_agent_steps(channel_id:, thread_id:, answer_id:)
    if answer_id.present?
      begin
        Slack::Client.stop_stream(workspace: @workspace, channel: channel_id, ts: answer_id)
      rescue AdapterError => error
        Rails.logger.info("slack.agent_steps.not_stopped error=#{error.class.name} message=#{error.message}")
      end
    end
    clear_agent_session(channel_id: channel_id, thread_id: thread_id)
  end

  # The short answer is already posted, so a full answer that cannot be is logged rather than failing the run.
  def post_answer_detail(channel_id, thread_id, finding)
    post_threaded_message(channel_id: channel_id, parent_message_id: thread_id, text: Slack::Messages::InvestigationRun.answer_detail_text(finding),
                          blocks: Slack::Messages::InvestigationRun.answer_detail(finding: finding))
  rescue AdapterError => error
    Rails.logger.warn({ event: "slack.answer_detail_not_posted", finding_id: finding.id, error: error.message }.to_json)
  end

  # The caption goes as the upload's comment. A note with no image, or a workspace that has not granted file uploads,
  # gets the caption as a plain message instead.
  def post_chart(channel_id, thread_id, chart)
    caption = Slack::Messages::ChartCaption.build(chart)
    return Slack::Client.post_message(workspace: @workspace, channel: channel_id, thread_ts: thread_id, text: caption) if chart.png.nil?

    Slack::Client.upload_file(
      workspace: @workspace, channel: channel_id, thread_ts: thread_id, filename: Slack::Messages::ChartCaption.filename(chart),
      content: chart.png, title: chart.title, comment: caption
    )
  rescue AdapterError::MissingPermission
    Slack::Client.post_message(workspace: @workspace, channel: channel_id, thread_ts: thread_id, text: caption)
  end

  def post_screenshot(channel_id, thread_id, shot)
    caption = Slack::Messages::ScreenshotCaption.build(shot)
    Slack::Client.upload_file(workspace: @workspace, channel: channel_id, thread_ts: thread_id, filename: shot.filename, content: shot.jpeg,
                              title: shot.caption.truncate(250), comment: caption)
  rescue AdapterError::MissingPermission
    Slack::Client.post_message(workspace: @workspace, channel: channel_id, thread_ts: thread_id, text: caption)
  end

  def announcement_text(incident) = "New incident: #{Slack::Mrkdwn.escape(Slack::Messages::IncidentDetail.title_for(incident))}"

  # Shown in push notifications, where a cancellation must not read as an update.
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

  # The thread gets the reply (built by reply for whether the newer blocks may be drawn), and each subscriber one short card
  # (Subscription.digest) built from digest's headline, body and icon, never a copy of the reply. A failed DM is logged
  # and skipped so one person who left the workspace or blocked the app does not stop the rest from hearing.
  def reply_and_notify_subscribers(channel_id, parent_message_id, subscriber_user_ids, incident:, text:, reply:, digest:)
    result = with_rich_blocks do |rich|
      post_threaded_message(channel_id: channel_id, parent_message_id: parent_message_id, text: text, blocks: reply.call(rich))
    end
    return result if subscriber_user_ids.empty?

    homepage_url = Slack::DashboardUrl.incident(incident)
    fallback = "#{incident.identifier}: #{digest[:headline]}"
    subscriber_user_ids.each do |user_id|
      with_rich_blocks do |rich|
        post_message(channel_id: user_id, text: fallback,
                     blocks: Slack::Messages::Subscription.digest(incident, **digest, homepage_url: homepage_url, rich: rich))
      end
    rescue AdapterError => e
      Rails.logger.warn({ event: "slack.subscriber_dm_failed", user_id: user_id, error: e.message }.to_json)
    end

    result
  end
end
