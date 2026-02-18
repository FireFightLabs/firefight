module Slack
  class IncidentMessageBuilder
    # Quick actions message posted and pinned in incident channel
    def self.quick_actions_blocks(incident)
      blocks = [
        {
          type: "header",
          text: {
            type: "plain_text",
            text: "#{incident.identifier}: #{incident.name || 'Untitled Incident'}"
          }
        }
      ]

      if incident.summary.present?
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: incident.summary }
        }
      end

      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: "#{severity_emoji(incident.incident_severity)} *Severity:* #{incident.incident_severity.name}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":bar_chart: *Status:* #{incident.incident_status.name}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: *Declared by:* <@#{incident.declared_by.platform_user_id}>" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Lead:* <@#{incident.lead.platform_user_id}>" } } if incident.lead

      blocks << { type: "divider" }
      blocks << {
        type: "actions",
        elements: quick_action_buttons(incident)
      }

      blocks
    end

    # Announcement posted to #incidents channel
    def self.announcement_blocks(incident)
      announcement_blocks_for({
        title: "#{incident.identifier}: #{incident.name || 'Untitled Incident'}",
        summary: incident.summary,
        severity_name: incident.incident_severity.name,
        severity_slug: incident.incident_severity.slug,
        status_name: incident.incident_status.name,
        reporter_id: incident.declared_by.platform_user_id,
        lead_id: incident.lead&.platform_user_id,
        channel_id: incident.channel_id
      })
    end

    # Shared announcement block builder used by both real announcements and preview
    def self.announcement_blocks_for(data)
      blocks = [
        {
          type: "header",
          text: { type: "plain_text", text: data[:title], emoji: true }
        }
      ]

      if data[:summary].present?
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: data[:summary] }
        }
      end

      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: "#{severity_emoji_for(data[:severity_slug])} *Severity:* #{data[:severity_name]}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":bar_chart: *Status:* #{data[:status_name]}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: *Reporter:* <@#{data[:reporter_id]}>" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Lead:* <@#{data[:lead_id]}>" } } if data[:lead_id]
      blocks << { type: "section", text: { type: "mrkdwn", text: ":hash: *Channel:* <##{data[:channel_id]}>" } } if data[:channel_id]
      blocks << { type: "divider" }
      blocks << {
        type: "actions",
        elements: [
          {
            type: "button",
            text: { type: "plain_text", text: ":globe_with_meridians: Incident homepage", emoji: true },
            action_id: Identifiers::PREVIEW_HOMEPAGE_DISABLED,
            style: "primary"
          },
          {
            type: "button",
            text: { type: "plain_text", text: ":pushpin: Subscribe", emoji: true },
            action_id: Identifiers::PREVIEW_SUBSCRIBE_DISABLED
          }
        ]
      }

      blocks
    end

    def self.quick_action_buttons(incident)
      buttons = []

      unless incident.lead
        buttons << {
          type: "button",
          text: { type: "plain_text", text: ":firefighter: Make me Lead", emoji: true },
          action_id: Identifiers::SET_INCIDENT_LEAD_SELF,
          value: incident.id
        }
      end

      buttons << {
        type: "button",
        text: { type: "plain_text", text: ":memo: Update summary", emoji: true },
        action_id: Identifiers::UPDATE_INCIDENT_SUMMARY,
        value: incident.id
      }

      buttons
    end

    # Compact inline format for the incident channel
    def self.status_update_blocks(incident, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil)
      severity_text = diff_text("Severity", previous_severity_name, incident.incident_severity.name)
      status_text = diff_text("Status", previous_status_name, incident.incident_status.name)

      context_parts = [
        "Updated by: *<@#{updated_by_platform_user_id}>*",
        severity_text,
        status_text
      ]

      blocks = [
        {
          type: "header",
          text: { type: "plain_text", text: "Incident updated", emoji: true }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: context_parts.join("  |  ") }
          ]
        }
      ]

      if message.present?
        blocks.insert(1, {
          type: "section",
          text: { type: "mrkdwn", text: message }
        })
      end

      blocks
    end

    # Vertical format with divider for #incidents announcement thread
    def self.status_update_announcement_blocks(incident, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil)
      severity_text = diff_text("Severity", previous_severity_name, incident.incident_severity.name)
      status_text = diff_text("Status", previous_status_name, incident.incident_status.name)

      blocks = [
        {
          type: "header",
          text: { type: "plain_text", text: "Incident updated", emoji: true }
        },
        { type: "divider" }
      ]

      if message.present?
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: message }
        }
      end

      blocks << { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: Updated by: *<@#{updated_by_platform_user_id}>*" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":rotating_light: #{severity_text}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":traffic_light: #{status_text}" } }

      blocks
    end

    def self.update_reminder_blocks(incident)
      [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: ":alarm_clock: It's time to provide a status update for *#{incident.identifier}*"
          }
        },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: ":writing_hand: Send an update", emoji: true },
              action_id: Identifiers::SEND_INCIDENT_UPDATE,
              value: incident.id
            }
          ]
        }
      ]
    end

    def self.resolution_blocks(incident, resolved_by_platform_user_id:)
      summary_text = incident.summary.present? ? "> #{incident.summary}" : "_No summary provided_"
      duration_text = format_duration(incident.time_to_resolve)

      [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":white_check_mark:  *Incident Resolved*" }
        },
        { type: "divider" },
        {
          type: "section",
          text: { type: "mrkdwn", text: summary_text }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "Resolved by <@#{resolved_by_platform_user_id}>  |  #{severity_emoji(incident.incident_severity)} #{incident.incident_severity.name}  |  Time to resolve: #{duration_text}" }
          ]
        }
      ]
    end

    def self.resolution_announcement_thread_blocks(incident, resolved_by_platform_user_id:)
      summary_text = incident.summary.present? ? incident.summary : "_No summary provided_"
      duration_text = format_duration(incident.time_to_resolve)

      [
        {
          type: "header",
          text: { type: "plain_text", text: "Incident Resolved", emoji: true }
        },
        { type: "divider" },
        {
          type: "section",
          text: { type: "mrkdwn", text: summary_text }
        },
        { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: Resolved by: *<@#{resolved_by_platform_user_id}>*" } },
        { type: "section", text: { type: "mrkdwn", text: "#{severity_emoji(incident.incident_severity)} Severity: *#{incident.incident_severity.name}*" } },
        { type: "section", text: { type: "mrkdwn", text: ":stopwatch: Time to resolve: *#{duration_text}*" } }
      ]
    end

    def self.reopen_blocks(incident, reopened_by_platform_user_id:, reason: nil)
      blocks = [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":rotating_light:  *Incident Reopened*" }
        },
        { type: "divider" }
      ]

      if reason.present?
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: "> #{reason}" }
        }
      end

      blocks << {
        type: "context",
        elements: [
          { type: "mrkdwn", text: "Reopened by <@#{reopened_by_platform_user_id}>  |  Status: #{incident.incident_status.name}" }
        ]
      }

      blocks
    end

    def self.reopen_announcement_thread_blocks(incident, reopened_by_platform_user_id:, reason: nil)
      blocks = [
        {
          type: "header",
          text: { type: "plain_text", text: "Incident Reopened", emoji: true }
        },
        { type: "divider" }
      ]

      if reason.present?
        blocks << { type: "section", text: { type: "mrkdwn", text: reason } }
      end

      blocks << { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: Reopened by: *<@#{reopened_by_platform_user_id}>*" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":bar_chart: Status: *#{incident.incident_status.name}*" } }

      blocks
    end

    def self.action_created_blocks(action)
      type_emoji, type_label = action_type_display(action)
      creator = "<@#{action.created_by.platform_user_id}>"

      blocks = [
        {
          type: "section",
          text: { type: "mrkdwn", text: "#{type_emoji}  *New #{type_label}*" }
        },
        { type: "divider" },
        {
          type: "section",
          text: { type: "mrkdwn", text: "> #{action.description}" }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "Added by #{creator}  |  #{action.assigned? ? "Assigned to <@#{action.assignee.platform_user_id}>" : "Unassigned"}" }
          ]
        }
      ]

      unless action.assigned?
        blocks << {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: ":raised_hands: I can take this", emoji: true },
              action_id: Identifiers::PICK_UP_ACTION,
              value: action.id
            }
          ]
        }
      end

      blocks
    end

    def self.action_picked_up_blocks(action)
      type_emoji, type_label = action_type_display(action)

      [
        {
          type: "section",
          text: { type: "mrkdwn", text: "#{type_emoji}  *New #{type_label}*" }
        },
        { type: "divider" },
        {
          type: "section",
          text: { type: "mrkdwn", text: "> #{action.description}" }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: ":large_blue_circle: Picked up by <@#{action.assignee.platform_user_id}>" }
          ]
        },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: ":white_check_mark: Mark as done", emoji: true },
              action_id: Identifiers::MARK_ACTION_DONE,
              value: action.id
            }
          ]
        }
      ]
    end

    def self.action_completed_blocks(action)
      type_emoji, _type_label = action_type_display(action)
      completer = action.assignee ? "<@#{action.assignee.platform_user_id}>" : "someone"

      [
        {
          type: "section",
          text: { type: "mrkdwn", text: "#{type_emoji}  ~#{action.description}~" }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: ":white_check_mark: Completed by #{completer}" }
          ]
        }
      ]
    end

    def self.action_from_reaction_blocks(action_type, message_text, incident_id, source_message_link)
      if action_type == IncidentAction::ACTION_TYPE_FOLLOWUP
        type_emoji = ":arrow_forward:"
        type_label = "follow-up"
        button_action_id = Identifiers::CREATE_FOLLOWUP_FROM_REACTION
      else
        type_emoji = ":boom:"
        type_label = "action"
        button_action_id = Identifiers::CREATE_ACTION_FROM_REACTION
      end

      preview = message_text.truncate(200)
      button_value = {
        incident_id: incident_id,
        source_message_text: message_text.truncate(3000),
        source_message_link: source_message_link
      }.to_json

      [
        {
          type: "section",
          text: { type: "mrkdwn", text: "#{type_emoji} *Create #{type_label} from this message?*\n> #{preview}" }
        },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: "Create #{type_label}", emoji: true },
              action_id: button_action_id,
              value: button_value,
              style: "primary"
            }
          ]
        }
      ]
    end

    def self.action_type_display(action)
      if action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP
        [ ":arrow_forward:", "follow-up" ]
      else
        [ ":boom:", "action" ]
      end
    end
    private_class_method :action_type_display

    def self.format_duration(minutes)
      return "N/A" if minutes.nil?

      if minutes < 60
        "#{minutes}m"
      elsif minutes < 1440
        hours = minutes / 60
        remaining_minutes = minutes % 60
        remaining_minutes > 0 ? "#{hours}h #{remaining_minutes}m" : "#{hours}h"
      else
        days = minutes / 1440
        remaining_hours = (minutes % 1440) / 60
        remaining_hours > 0 ? "#{days}d #{remaining_hours}h" : "#{days}d"
      end
    end
    private_class_method :format_duration

    def self.diff_text(label, previous_name, current_name)
      if previous_name.present? && previous_name != current_name
        "#{label}: ~#{previous_name}~ → *#{current_name}*"
      else
        "#{label}: *#{current_name}*"
      end
    end
    private_class_method :diff_text

    def self.severity_emoji(severity)
      severity_emoji_for(severity.slug)
    end

    def self.severity_emoji_for(slug)
      case slug
      when "critical" then ":red_circle:"
      when "major" then ":large_yellow_circle:"
      when "minor" then ":fire:"
      else ":white_circle:"
      end
    end
  end
end
