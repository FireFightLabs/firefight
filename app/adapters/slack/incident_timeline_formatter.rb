module Slack
  class IncidentTimelineFormatter
    EVENT_STYLE = {
      IncidentEvent::INCIDENT_CREATED => { emoji: ":rotating_light:", title: "Incident declared" },
      IncidentEvent::INCIDENT_UPDATED => { emoji: ":memo:", title: "Incident updated" },
      IncidentEvent::INCIDENT_ACCEPTED => { emoji: ":white_check_mark:", title: "Incident accepted" },
      IncidentEvent::LEAD_ASSIGNED => { emoji: ":firefighter:", title: "Lead assigned" },
      IncidentEvent::INCIDENT_ESCALATED => { emoji: ":rotating_light:", title: "Incident escalated" },
      IncidentEvent::INCIDENT_RESOLVED => { emoji: ":white_check_mark:", title: "Incident resolved" },
      IncidentEvent::INCIDENT_REOPENED => { emoji: ":warning:", title: "Incident reopened" },
      IncidentEvent::RELATIONSHIP_CREATED => { emoji: ":link:", title: "Incident linked" },
      IncidentEvent::MARKED_DUPLICATE => { emoji: ":repeat:", title: "Marked duplicate" },
      IncidentEvent::MERGED_INTO => { emoji: ":repeat:", title: "Merged into incident" },
      IncidentEvent::ACTION_CREATED => { emoji: ":clipboard:", title: "Action created" },
      IncidentEvent::ACTION_PICKED_UP => { emoji: ":raised_hands:", title: "Action picked up" },
      IncidentEvent::ACTION_COMPLETED => { emoji: ":white_check_mark:", title: "Action completed" },
      IncidentEvent::ACTION_RENAMED => { emoji: ":pencil2:", title: "Action renamed" },
      IncidentEvent::ACTION_REOPENED => { emoji: ":leftwards_arrow_with_hook:", title: "Action reopened" },
      IncidentEvent::ACTION_UNASSIGNED => { emoji: ":bust_in_silhouette:", title: "Action unassigned" },
      IncidentEvent::POSTMORTEM_GENERATED => { emoji: ":scroll:", title: "Postmortem generated" },
      IncidentEvent::POSTMORTEM_STARTED => { emoji: ":scroll:", title: "Postmortem started" },
      IncidentEvent::POSTMORTEM_EDITED => { emoji: ":pencil2:", title: "Postmortem edited" },
      IncidentEvent::MESSAGE_PINNED => { emoji: ":pushpin:", title: "Message pinned" },
      IncidentEvent::MESSAGE_UNPINNED => { emoji: ":round_pushpin:", title: "Message unpinned" },
      IncidentEvent::MESSAGE_FILE_SHARED => { emoji: ":paperclip:", title: "File shared" },
      IncidentEvent::ESCALATION_ACKNOWLEDGED => { emoji: ":white_check_mark:", title: "Escalation acknowledged" },
      IncidentEvent::ESCALATION_NUDGED => { emoji: ":bell:", title: "Escalation reminder sent" },
      IncidentEvent::MILESTONE_NOTED => { emoji: ":sparkles:", title: "AI note" },
      IncidentEvent::INVESTIGATION_STARTED => { emoji: ":mag:", title: "Investigation started" },
      IncidentEvent::INVESTIGATION_ANSWERED => { emoji: ":mag:", title: "Investigation answered" },
      IncidentEvent::INVESTIGATION_STOPPED => { emoji: ":mag:", title: "Investigation stopped" },
      IncidentEvent::FIX_APPLIED => { emoji: ":hammer_and_wrench:", title: "Fix applied" },
      IncidentEvent::FIX_STEP_DONE => { emoji: ":white_check_mark:", title: "Fix step done" },
      IncidentEvent::FIX_STEP_FAILED => { emoji: ":x:", title: "Fix step failed" },
      IncidentEvent::FIX_STEP_MARKED_DONE => { emoji: ":white_check_mark:", title: "Fix step marked done" },
      IncidentEvent::FIX_CANCELLED => { emoji: ":no_entry_sign:", title: "Fix cancelled" },
      IncidentEvent::FIX_ENDED => { emoji: ":hammer_and_wrench:", title: "Fix finished" },
      IncidentEvent::FIX_UNDO_WRITTEN => { emoji: ":leftwards_arrow_with_hook:", title: "Undo written" },
      IncidentEvent::PAGE_RAISED => { emoji: ":rotating_light:", title: "Paged" },
      IncidentEvent::PAGE_FAILED => { emoji: ":warning:", title: "Page not raised" },
      IncidentEvent::PAGE_ACKNOWLEDGED => { emoji: ":white_check_mark:", title: "Page acknowledged" },
      IncidentEvent::PAGE_ESCALATED => { emoji: ":rotating_light:", title: "Page escalated" },
      IncidentEvent::PAGE_NOTED => { emoji: ":memo:", title: "Note on the page" },
      IncidentEvent::PAGE_RESOLVED => { emoji: ":white_check_mark:", title: "Page resolved" },
      IncidentEvent::PAGE_SYNC_FAILED => { emoji: ":warning:", title: "Page not updated" }
    }.freeze

    CHANGE_VALUE_LIMIT = 80
    # Three or fewer changes read on one line, as the update message itself lays them out.
    INLINE_CHANGES = 3

    def self.label_for(event)
      EVENT_STYLE.dig(event.event_type, :title) || event.description || event.event_type
    end
    private_class_method :label_for

    def self.emoji_for(event)
      EVENT_STYLE.dig(event.event_type, :emoji) || ":small_blue_diamond:"
    end
    private_class_method :emoji_for

    # Someone with no Slack account, a person or a machine, is named rather than shown as Firefight's own doing.
    def self.actor_mention_for(event)
      user_id = (event.metadata || {})["user_id"] || event.actor&.platform_user_id
      return Mrkdwn.person(user_id, event.actor&.actor_display_name) if user_id.present? || event.actor
      return Mrkdwn.escape(event.tool_person) if event.tool_person

      "System"
    end
    private_class_method :actor_mention_for

    def self.to_block(event)
      details = details_for(event)
      actor = actor_mention_for(event)

      section_text = "#{emoji_for(event)} *#{label_for(event)}*"
      section_text += "\n#{details}" if details.present?
      section_text = section_text.truncate(Slack::Messages::Formatting::SECTION_TEXT_LIMIT, separator: "\n", omission: "\n…")

      unix_ts = event.created_at.to_i
      fallback = event.created_at.in_time_zone.strftime("%Y-%m-%d %H:%M")
      context_text = "<!date^#{unix_ts}^{date_short_pretty} at {time}|#{fallback}> · #{actor}"

      {
        section: {
          type: "section",
          text: { type: "mrkdwn", text: section_text }
        },
        context: {
          type: "context",
          elements: [ { type: "mrkdwn", text: context_text } ]
        }
      }
    end

    def self.to_blocks(events)
      events.flat_map do |event|
        block = to_block(event)
        [ block[:section], block[:context] ]
      end
    end

    def self.details_for(event)
      details = event.metadata || {}

      case event.event_type
      when *IncidentEvent::UPDATE_MESSAGE_EVENTS
        update_details(event)
      when IncidentEvent::INCIDENT_ESCALATED
        target = details["escalated_to_platform_user_id"]
        name = details["escalated_to_name"]
        [ ("to #{Mrkdwn.person(target, name)}" if target.present? || name.present?), quoted_reason(details) ].compact.join("\n")
      when IncidentEvent::MESSAGE_PINNED, IncidentEvent::MESSAGE_UNPINNED
        details["permalink"].presence
      when IncidentEvent::MESSAGE_FILE_SHARED
        file_name = details["file_name"].presence && Mrkdwn.escape(details["file_name"])
        permalink = details["permalink"].present? ? "<#{details['permalink']}|Open in Slack>" : nil
        [ file_name, permalink ].compact.join(" · ")
      when IncidentEvent::INCIDENT_REOPENED
        quoted_reason(details)
      when IncidentEvent::ESCALATION_ACKNOWLEDGED
        "by #{Mrkdwn.person(details['acknowledged_by_platform_user_id'], details['acknowledged_by_name'])}"
      when IncidentEvent::ESCALATION_NUDGED
        "to #{Mrkdwn.person(details['escalated_to_platform_user_id'], details['escalated_to_name'])}"
      when IncidentEvent::INVESTIGATION_ANSWERED
        details["message"]
      when *IncidentEvent::FIX_STEP_EVENTS
        fix_step_details(event.fix_step)
      when *IncidentEvent::FIX_EVENTS
        details["message"].presence && Mrkdwn.escape(details["message"])
      when *IncidentEvent::PAGE_EVENTS
        subject = Mrkdwn.escape(details["subject"].to_s)
        subject = "<#{Mrkdwn.escape(details['url'])}|#{subject}>" if details["url"].to_s.start_with?("https://") && subject.present?
        [ subject.presence, details["message"].presence && Slack::Messages::Formatting.quoted_markdown(Mrkdwn.escape(details["message"])) ].compact.join("\n")
      when IncidentEvent::MILESTONE_NOTED
        link = details["permalink"].present? ? "<#{details['permalink']}|Open in Slack>" : nil
        [ details["statement"], link ].compact.join(" · ")
      else
        eventable = event.eventable
        message = if eventable&.respond_to?(:message)
          eventable.message
        elsif eventable&.respond_to?(:description)
          eventable.description
        end

        message.presence || details["reason"]
      end
    end
    private_class_method :details_for

    # The step by its name, then what it produced, with the link where the words name it.
    def self.fix_step_details(step)
      link = step.link
      result = if link
        "#{Mrkdwn.escape(link.before)}<#{link.href}|#{Mrkdwn.escape(link.label)}>#{Mrkdwn.escape(link.after)}"
      else
        step.result && Mrkdwn.escape(step.result)
      end
      [ Mrkdwn.escape(step.title).presence, result ].compact.join("\n")
    end
    private_class_method :fix_step_details

    # The reason a person gave, quoted as the channel showed it.
    def self.quoted_reason(details)
      Slack::Messages::Formatting.quoted_markdown(details["reason"]) if details["reason"].present?
    end
    private_class_method :quoted_reason

    # The message as the channel showed it, then what changed with its before and after.
    def self.update_details(event)
      message = event.update_message
      changes = event.update_changes.map { |change| change_line(change) }
      parts = []
      parts << Slack::Messages::Formatting.quoted_markdown(message) if message
      parts << changes.join(changes.size > INLINE_CHANGES ? "\n" : "  ·  ") if changes.any?
      parts.join("\n")
    end
    private_class_method :update_details

    def self.change_line(change)
      before = change_value(change, change.before)
      after = change_value(change, change.after)
      if after
        Slack::Messages::Formatting.diff_text(change.label, before, after)
      else
        "#{change.label}: ~#{before}~ → cleared"
      end
    end
    private_class_method :change_line

    def self.change_value(change, value)
      return nil if value.blank?

      if change.kind == IncidentUpdate::CHANGE_KIND_TIME
        time = Time.iso8601(value)
        return "<!date^#{time.to_i}^{date_short_pretty} at {time}|#{time.utc.strftime('%Y-%m-%d %H:%M UTC')}>"
      end

      Slack::Mrkdwn.escape(IncidentUpdate::MessageText.lead(value, limit: CHANGE_VALUE_LIMIT))
    rescue ArgumentError
      Slack::Mrkdwn.escape(value)
    end
    private_class_method :change_value
  end
end
