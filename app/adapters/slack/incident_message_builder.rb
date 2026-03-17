module Slack
  class IncidentMessageBuilder
    # Quick actions message posted and pinned in incident channel
    def self.quick_actions_blocks(incident)
      blocks = [
        {
          type: "header",
          text: {
            type: "plain_text",
            text: ":rotating_light: #{incident.identifier} \u00B7 #{incident.name || 'Untitled Incident'}",
            emoji: true
          }
        }
      ]

      if incident.summary.present?
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: "_#{incident.summary}_" }
        }
      end

      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":fire: *Severity:* #{incident.incident_severity.name}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":construction: *Status:* #{incident.incident_status.name}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Lead:* <@#{incident.lead.platform_user_id}>" } } if incident.lead
      blocks << { type: "section", text: { type: "mrkdwn", text: ":mega: *Declared by:* <@#{incident.declared_by.platform_user_id}>" } }

      relationship_text = relationship_summary(incident)
      blocks << { type: "section", text: { type: "mrkdwn", text: relationship_text } } if relationship_text

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
        title: "#{incident.identifier} \u00B7 #{incident.name || 'Untitled Incident'}",
        summary: incident.summary,
        severity_name: incident.incident_severity.name,
        status_name: incident.incident_status.name,
        type_name: incident.incident_type&.name,
        reporter_id: incident.declared_by.platform_user_id,
        lead_id: incident.lead&.platform_user_id,
        channel_id: incident.channel_id,
        relationship_text: relationship_summary(incident)
      })
    end

    # Shared announcement block builder used by both real announcements and preview
    def self.announcement_blocks_for(data)
      blocks = [
        {
          type: "header",
          text: { type: "plain_text", text: ":rotating_light: #{data[:title]}", emoji: true }
        }
      ]

      if data[:summary].present?
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: "_#{data[:summary]}_" }
        }
      end

      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":fire: *Severity:* #{data[:severity_name]}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":construction: *Status:* #{data[:status_name]}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Lead:* <@#{data[:lead_id]}>" } } if data[:lead_id]
      blocks << { type: "section", text: { type: "mrkdwn", text: ":mega: *Reporter:* <@#{data[:reporter_id]}>" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":speech_balloon: *Channel:* <##{data[:channel_id]}>" } } if data[:channel_id]
      blocks << { type: "section", text: { type: "mrkdwn", text: data[:relationship_text] } } if data[:relationship_text]
      blocks << { type: "divider" }
      blocks << {
        type: "actions",
        elements: [
          {
            type: "button",
            text: { type: "plain_text", text: ":globe_with_meridians: Incident homepage", emoji: true },
            action_id: Identifiers::PREVIEW_HOMEPAGE_DISABLED
          },
          {
            type: "button",
            text: { type: "plain_text", text: ":bell: Subscribe", emoji: true },
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

      buttons << {
        type: "button",
        text: { type: "plain_text", text: ":fire_engine: Escalate", emoji: true },
        action_id: Identifiers::ESCALATE_INCIDENT,
        value: incident.id
      }

      buttons
    end

    # Compact inline format for the incident channel
    def self.status_update_blocks(incident, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
      severity_text = diff_text("Severity", previous_severity_name, incident.incident_severity.name)
      status_text = diff_text("Status", previous_status_name, incident.incident_status.name)
      type_text = type_diff_text(previous_type_name, incident.incident_type&.name)

      context_parts = [
        "Updated by: *<@#{updated_by_platform_user_id}>*",
        severity_text,
        status_text
      ]
      context_parts << type_text if type_text

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
    def self.status_update_announcement_blocks(incident, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
      severity_text = diff_text("Severity", previous_severity_name, incident.incident_severity.name)
      status_text = diff_text("Status", previous_status_name, incident.incident_status.name)
      type_text = type_diff_text(previous_type_name, incident.incident_type&.name)

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
      blocks << { type: "section", text: { type: "mrkdwn", text: ":fire: #{severity_text}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":construction: #{status_text}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":label: #{type_text}" } } if type_text

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

    def self.escalation_blocks(incident, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
      blocks = [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":rotating_light:  *Incident Escalated*" }
        },
        { type: "divider" },
        {
          type: "section",
          text: { type: "mrkdwn", text: "Escalated to <@#{escalated_to_platform_user_id}>" }
        }
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
          { type: "mrkdwn", text: "Escalated by <@#{escalated_by_platform_user_id}>  |  Status: #{incident.incident_status.name}" }
        ]
      }

      blocks
    end

    def self.escalation_announcement_thread_blocks(incident, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
      blocks = [
        {
          type: "header",
          text: { type: "plain_text", text: "Incident Escalated", emoji: true }
        },
        { type: "divider" },
        {
          type: "section",
          text: { type: "mrkdwn", text: ":bust_in_silhouette: Escalated to: *<@#{escalated_to_platform_user_id}>*" }
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: ":bust_in_silhouette: Escalated by: *<@#{escalated_by_platform_user_id}>*" }
        }
      ]

      if reason.present?
        blocks << { type: "section", text: { type: "mrkdwn", text: reason } }
      end

      blocks
    end

    def self.escalation_direct_message_blocks(incident, escalated_by_platform_user_id:, escalation_event_id:, reason: nil)
      blocks = [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":rotating_light: *#{incident.identifier}* has been escalated to you" }
        },
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "Escalated by <@#{escalated_by_platform_user_id}> in <##{incident.channel_id}>."
          }
        }
      ]

      if reason.present?
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: "> #{reason}" }
        }
      end

      blocks << {
        type: "actions",
        elements: [
          {
            type: "button",
            text: { type: "plain_text", text: ":white_check_mark: Acknowledge", emoji: true },
            action_id: Identifiers::ACKNOWLEDGE_ESCALATION,
            style: "primary",
            value: {
              incident_id: incident.id,
              escalation_event_id: escalation_event_id
            }.to_json
          }
        ]
      }

      blocks
    end

    def self.escalation_acknowledged_blocks(incident, acknowledged_by_platform_user_id:, escalated_to_platform_user_id:)
      [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":white_check_mark: *Escalation acknowledged*" }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "<@#{acknowledged_by_platform_user_id}> acknowledged escalation to <@#{escalated_to_platform_user_id}> for *#{incident.identifier}*." }
          ]
        }
      ]
    end

    def self.escalation_nudge_direct_message_blocks(incident, escalated_by_platform_user_id:, escalation_event_id:, reason: nil)
      blocks = [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":bell: Reminder: *#{incident.identifier}* is waiting for your response." }
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: "Escalated by <@#{escalated_by_platform_user_id}> in <##{incident.channel_id}>." }
        }
      ]

      if reason.present?
        blocks << { type: "section", text: { type: "mrkdwn", text: "> #{reason}" } }
      end

      blocks << {
        type: "actions",
        elements: [
          {
            type: "button",
            text: { type: "plain_text", text: ":white_check_mark: Acknowledge", emoji: true },
            action_id: Identifiers::ACKNOWLEDGE_ESCALATION,
            style: "primary",
            value: {
              incident_id: incident.id,
              escalation_event_id: escalation_event_id
            }.to_json
          }
        ]
      }

      blocks
    end

    def self.related_link_blocks(source, target, linked_by_platform_user_id:)
      [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":link: *Incident linked*" }
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: "Linked as related to *#{target.identifier}*: #{target.name || 'Untitled Incident'}#{target.channel_id ? " (<##{target.channel_id}>)" : ""}" }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "Linked by <@#{linked_by_platform_user_id}>" }
          ]
        }
      ]
    end

    def self.duplicate_source_blocks(source, canonical, linked_by_platform_user_id:)
      [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":no_entry_sign: *Incident merged*" }
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: "This incident has been marked as a duplicate and merged into *#{canonical.identifier}*: #{canonical.name || 'Untitled Incident'}#{canonical.channel_id ? " (<##{canonical.channel_id}>)" : ""}" }
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: ":point_right: Please continue in <##{canonical.channel_id}>" }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "Merged by <@#{linked_by_platform_user_id}>" }
          ]
        }
      ]
    end

    def self.duplicate_canonical_blocks(source, canonical, linked_by_platform_user_id:)
      [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":incoming_envelope: *Duplicate merged in*" }
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: "*#{source.identifier}*: #{source.name || 'Untitled Incident'}#{source.channel_id ? " (<##{source.channel_id}>)" : ""} has been marked as a duplicate of this incident." }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "Merged by <@#{linked_by_platform_user_id}>" }
          ]
        }
      ]
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

      if action.assigned?
        blocks << {
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
      else
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

    def self.shoutout_blocks(incident, from_user_id:, recipient_user_id:, message:)
      [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: ":heart_on_fire: *Shoutout*\n<@#{from_user_id}> gave a shoutout to <@#{recipient_user_id}>\n> #{message}"
          }
        },
        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "During <##{incident.channel_id}> · #{incident.identifier}" }
          ]
        }
      ]
    end

    def self.shoutout_from_reaction_blocks(incident_id)
      [
        {
          type: "section",
          text: { type: "mrkdwn", text: ":heart_on_fire: *Give a shoutout?*\nRecognize someone on your team for their work on this incident." }
        },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: "Give a shoutout", emoji: true },
              action_id: Identifiers::SHOUTOUT_FROM_REACTION,
              value: { incident_id: incident_id }.to_json,
              style: "primary"
            }
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

    def self.type_diff_text(previous_name, current_name)
      return nil if previous_name.nil? && current_name.nil?

      if previous_name.nil?
        "Type: *#{current_name}*"
      elsif current_name.nil?
        "Type: ~#{previous_name}~ → _none_"
      elsif previous_name != current_name
        "Type: ~#{previous_name}~ → *#{current_name}*"
      else
        "Type: *#{current_name}*"
      end
    end
    private_class_method :type_diff_text

    def self.diff_text(label, previous_name, current_name)
      if previous_name.present? && previous_name != current_name
        "#{label}: ~#{previous_name}~ → *#{current_name}*"
      else
        "#{label}: *#{current_name}*"
      end
    end
    private_class_method :diff_text

    def self.relationship_summary(incident)
      parts = []

      related = incident.related_incidents.to_a
      if related.any?
        links = related.map { |i| "#{i.identifier}#{i.channel_id ? " (<##{i.channel_id}>)" : ""}" }
        parts << ":link: *Related:* #{links.join(', ')}"
      end

      dupes = incident.duplicates
      if dupes.any?
        links = dupes.map { |i| "#{i.identifier}#{i.channel_id ? " (<##{i.channel_id}>)" : ""}" }
        parts << ":incoming_envelope: *Duplicates:* #{links.join(', ')}"
      end

      canonical = incident.duplicate_of
      if canonical
        parts << ":no_entry_sign: *Duplicate of:* #{canonical.identifier}#{canonical.channel_id ? " (<##{canonical.channel_id}>)" : ""}"
      end

      parts.any? ? parts.join("\n") : nil
    end
    private_class_method :relationship_summary

    def self.severity_emoji(severity)
      ":fire:"
    end

    def self.severity_emoji_for(slug)
      ":fire:"
    end
  end
end
