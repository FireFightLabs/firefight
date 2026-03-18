module Slack
  class ModalBuilder
    def self.incident_creation_form(workspace:, selected_severity_slug: nil)
      severities = workspace.incident_severities.active.ordered
      default_severity = severities.find(&:is_default?) || severities.last
      selected_severity = if selected_severity_slug
        severities.find { |s| s.slug == selected_severity_slug } || default_severity
      else
        default_severity
      end

      severity_options = severities.map do |severity|
        {
          text: { type: "plain_text", text: severity.name },
          value: severity.slug
        }
      end

      initial_option = {
        text: { type: "plain_text", text: selected_severity.name },
        value: selected_severity.slug
      }

      {
        type: "modal",
        callback_id: Identifiers::INCIDENT_CREATION_MODAL,
        title: {
          type: "plain_text",
          text: "Declare an incident"
        },
        submit: {
          type: "plain_text",
          text: "Declare"
        },
        close: {
          type: "plain_text",
          text: "Cancel"
        },
        blocks: [
          {
            type: "input",
            block_id: "name_block",
            element: {
              type: "plain_text_input",
              action_id: "name_input",
              placeholder: {
                type: "plain_text",
                text: "Write something"
              },
              max_length: 200
            },
            label: {
              type: "plain_text",
              text: "Incident name"
            },
            hint: {
              type: "plain_text",
              text: "Give a short description of what is happening. If you'd like to, you can leave it blank and change it later"
            },
            optional: true
          },
          {
            type: "input",
            block_id: "severity_block",
            dispatch_action: true,
            element: {
              type: "static_select",
              action_id: Identifiers::INCIDENT_CREATION_SEVERITY_SELECT,
              placeholder: {
                type: "plain_text",
                text: "Select severity"
              },
              options: severity_options,
              initial_option: initial_option
            },
            label: {
              type: "plain_text",
              text: "Severity"
            }
          }.tap do |block|
            if selected_severity.description.present?
              block[:hint] = { type: "plain_text", text: selected_severity.description }
            end
          end,
          {
            type: "input",
            block_id: "summary_block",
            element: {
              type: "plain_text_input",
              action_id: "summary_input",
              multiline: true,
              placeholder: {
                type: "plain_text",
                text: "Think about what you'd like to read if you were coming to the incident fresh..."
              },
              max_length: 3000
            },
            label: {
              type: "plain_text",
              text: "Summary"
            },
            hint: {
              type: "plain_text",
              text: "Your current understanding of what happened in the incident, and the impact it had. It's fine to go into detail here."
            },
            optional: true
          },
          {
            type: "input",
            block_id: "visibility_block",
            element: {
              type: "static_select",
              action_id: "visibility_select",
              options: [
                {
                  text: { type: "plain_text", text: "Everyone (public)" },
                  value: Incident::VISIBILITY_PUBLIC
                },
                {
                  text: { type: "plain_text", text: "Private" },
                  value: Incident::VISIBILITY_PRIVATE
                }
              ],
              initial_option: {
                text: { type: "plain_text", text: "Everyone (public)" },
                value: Incident::VISIBILITY_PUBLIC
              }
            },
            label: {
              type: "plain_text",
              text: "Who should be able to see this incident?"
            },
            hint: {
              type: "plain_text",
              text: "Public incidents are visible to everyone in the workspace. Private incidents are only accessible to invited members."
            }
          }
        ]
      }
    end

    def self.incident_created_confirmation(incident, team_id:)
      channel_link = "slack://channel?team=#{team_id}&id=#{incident.channel_id}"

      {
        type: "modal",
        title: {
          type: "plain_text",
          text: "Incident declared"
        },
        close: {
          type: "plain_text",
          text: "Close"
        },
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "We've created <##{incident.channel_id}> as a dedicated space to respond to this incident with your team."
            }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: ":slack: Join incident channel",
                  emoji: true
                },
                url: channel_link
              }
            ]
          }
        ]
      }
    end

    def self.home_modal(channel_id:)
      {
        type: "modal",
        callback_id: Identifiers::INCIDENT_HOME_MODAL,
        private_metadata: { channel_id: channel_id }.to_json,
        title: {
          type: "plain_text",
          text: "Incident Home"
        },
        submit: {
          type: "plain_text",
          text: "Continue"
        },
        close: {
          type: "plain_text",
          text: "Close"
        },
        blocks: [
          {
            type: "input",
            dispatch_action: true,
            block_id: "action_select_block",
            element: {
              type: "static_select",
              action_id: Identifiers::HOME_ACTION_SELECT,
              placeholder: {
                type: "plain_text",
                text: "Type a command or search..."
              },
              option_groups: home_modal_option_groups
            },
            label: {
              type: "plain_text",
              text: "Choose an action"
            },
            hint: {
              type: "plain_text",
              text: "Search and run any Firefight action from one place."
            }
          },
          {
            type: "section",
            block_id: "command_details_block",
            text: {
              type: "mrkdwn",
              text: "*For example:*\n\n:pencil2:  Update the current status or severity `/ff status`\n\n:rotating_light:  Escalate to someone who can help `/ff escalate`\n\n:dart:  Assign the incident lead role `/ff lead`\n\n:lock:  Close the incident when it's resolved `/ff close`"
            }
          }
        ]
      }
    end

    def self.home_modal_option_groups
      [
        {
          label: { type: "plain_text", text: "Quick actions", emoji: true },
          options: [
            { text: { type: "plain_text", text: ":pencil2: Update status",           emoji: true }, value: Identifiers::HOME_ACTION_STATUS },
            { text: { type: "plain_text", text: ":warning: Change severity",         emoji: true }, value: Identifiers::HOME_ACTION_SEVERITY },
            { text: { type: "plain_text", text: ":memo: Update incident summary",    emoji: true }, value: Identifiers::HOME_ACTION_SUMMARY }
          ]
        },
        {
          label: { type: "plain_text", text: "Communicate", emoji: true },
          options: [
            { text: { type: "plain_text", text: ":rotating_light: Escalate to someone", emoji: true }, value: Identifiers::HOME_ACTION_ESCALATE },
            { text: { type: "plain_text", text: ":busts_in_silhouette: Invite responders", emoji: true }, value: Identifiers::HOME_ACTION_INVITE }
          ]
        },
        {
          label: { type: "plain_text", text: "Coordinate", emoji: true },
          options: [
            { text: { type: "plain_text", text: ":dart: Set incident lead", emoji: true }, value: Identifiers::HOME_ACTION_LEAD },
            { text: { type: "plain_text", text: ":ballot_box_with_check: Manage actions", emoji: true }, value: Identifiers::HOME_ACTION_ACTIONS },
            { text: { type: "plain_text", text: ":lock: Close incident",    emoji: true }, value: Identifiers::HOME_ACTION_CLOSE }
          ]
        },
        {
          label: { type: "plain_text", text: "Review", emoji: true },
          options: [
            { text: { type: "plain_text", text: ":clock1: View timeline",              emoji: true }, value: Identifiers::HOME_ACTION_TIMELINE },
            { text: { type: "plain_text", text: ":clipboard: List active incidents",   emoji: true }, value: Identifiers::HOME_ACTION_LIST },
            { text: { type: "plain_text", text: ":page_facing_up: Generate postmortem", emoji: true }, value: Identifiers::HOME_ACTION_POSTMORTEM }
          ]
        },
        {
          label: { type: "plain_text", text: "New", emoji: true },
          options: [
            { text: { type: "plain_text", text: ":fire: Create a new incident", emoji: true }, value: Identifiers::HOME_ACTION_NEW }
          ]
        }
      ]
    end

    def self.summary_modal(incident, private_metadata: nil)
      initial_value = incident.summary.present? ? { initial_value: incident.summary } : {}
      metadata = private_metadata || incident.id

      {
        type: "modal",
        callback_id: Identifiers::UPDATE_SUMMARY_MODAL,
        notify_on_close: true,
        private_metadata: metadata,
        title: {
          type: "plain_text",
          text: "Update Summary"
        },
        submit: {
          type: "plain_text",
          text: "Save"
        },
        close: {
          type: "plain_text",
          text: "Cancel"
        },
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*#{incident.identifier}*: #{incident.name || 'Untitled Incident'}"
            }
          },
          {
            type: "input",
            block_id: "summary_block",
            element: {
              type: "plain_text_input",
              action_id: "summary_input",
              multiline: true,
              placeholder: {
                type: "plain_text",
                text: "What is your current understanding of the incident and its impact?"
              },
              max_length: 3000
            }.merge(initial_value),
            label: {
              type: "plain_text",
              text: "Summary"
            },
            hint: {
              type: "plain_text",
              text: "Describe what happened, the impact, and the current state. It's fine to go into detail."
            },
            optional: true
          }
        ]
      }
    end

    def self.lead_modal(incident)
      initial_user = incident.lead&.platform_user_id
      element = {
        type: "users_select",
        action_id: "lead_select",
        placeholder: {
          type: "plain_text",
          text: "Select a person"
        }
      }
      element[:initial_user] = initial_user if initial_user

      {
        type: "modal",
        callback_id: Identifiers::SET_LEAD_MODAL,
        private_metadata: incident.id,
        title: {
          type: "plain_text",
          text: "Set Incident Lead"
        },
        submit: {
          type: "plain_text",
          text: "Assign"
        },
        close: {
          type: "plain_text",
          text: "Cancel"
        },
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*#{incident.identifier}*: #{incident.name || 'Untitled Incident'}"
            }
          },
          {
            type: "input",
            block_id: "lead_block",
            element: element,
            label: {
              type: "plain_text",
              text: "Incident Lead"
            },
            hint: {
              type: "plain_text",
              text: "The lead coordinates the incident response and provides regular updates."
            }
          }
        ]
      }
    end

    def self.incident_update_modal(incident, private_metadata: nil)
      workspace = incident.workspace
      statuses = workspace.incident_statuses.active.ordered
      severities = workspace.incident_severities.active.ordered
      types = workspace.incident_types.active.ordered
      metadata = private_metadata || incident.id

      current_status = incident.incident_status
      current_severity = incident.incident_severity

      status_options = statuses.map do |status|
        option = {
          text: { type: "plain_text", text: status.name },
          value: status.slug
        }
        option[:description] = { type: "plain_text", text: status.description } if status.description.present?
        option
      end

      severity_options = severities.map do |severity|
        option = {
          text: { type: "plain_text", text: severity.name },
          value: severity.slug
        }
        option[:description] = { type: "plain_text", text: severity.description } if severity.description.present?
        option
      end

      initial_status = status_options.find { |o| o[:value] == current_status.slug }
      initial_severity = severity_options.find { |o| o[:value] == current_severity.slug }

      blocks = [
        {
          type: "input",
          block_id: "status_block",
          element: {
            type: "static_select",
            action_id: "status_select",
            options: status_options,
            initial_option: initial_status
          }.compact,
          label: { type: "plain_text", text: "Status" }
        },
        {
          type: "input",
          block_id: "severity_block",
          element: {
            type: "static_select",
            action_id: "severity_select",
            options: severity_options,
            initial_option: initial_severity
          }.compact,
          label: { type: "plain_text", text: "Severity" }
        }
      ]

      if types.any?
        blocks << type_block(types, incident.incident_type)
      end

      blocks << {
        type: "input",
        block_id: "message_block",
        element: {
          type: "plain_text_input",
          action_id: "message_input",
          multiline: true,
          placeholder: {
            type: "plain_text",
            text: "What's happening at the moment? What are you doing next?"
          },
          max_length: 3000
        },
        label: { type: "plain_text", text: "Message" },
        optional: true
      }

      blocks << {
        type: "input",
        block_id: "next_update_block",
        element: {
          type: "static_select",
          action_id: "next_update_select",
          placeholder: {
            type: "plain_text",
            text: "Select a time"
          },
          options: next_update_options
        },
        label: { type: "plain_text", text: "When will you provide the next update?" },
        optional: true
      }

      {
        type: "modal",
        callback_id: Identifiers::INCIDENT_UPDATE_MODAL,
        notify_on_close: true,
        private_metadata: metadata,
        title: {
          type: "plain_text",
          text: "Incident update"
        },
        submit: {
          type: "plain_text",
          text: "Send update"
        },
        close: {
          type: "plain_text",
          text: "Cancel"
        },
        blocks: blocks
      }
    end

    NEXT_UPDATE_OPTIONS = [
      { label: "5 minutes", value: "5" },
      { label: "15 minutes", value: "15" },
      { label: "30 minutes", value: "30" },
      { label: "1 hour", value: "60" },
      { label: "3 hours", value: "180" },
      { label: "1 day", value: "1440" },
      { label: "7 days", value: "10080" }
    ].freeze

    def self.type_block(types, current_type)
      type_options = types.map do |type|
        option = {
          text: { type: "plain_text", text: type.name },
          value: type.slug
        }
        option[:description] = { type: "plain_text", text: type.description } if type.description.present?
        option
      end

      initial_type = current_type ? type_options.find { |o| o[:value] == current_type.slug } : nil

      element = {
        type: "static_select",
        action_id: "type_select",
        placeholder: { type: "plain_text", text: "Select a type" },
        options: type_options
      }
      element[:initial_option] = initial_type if initial_type

      {
        type: "input",
        block_id: "type_block",
        element: element,
        label: { type: "plain_text", text: "Type" },
        optional: true
      }
    end
    private_class_method :type_block

    def self.next_update_options
      NEXT_UPDATE_OPTIONS.map do |opt|
        {
          text: { type: "plain_text", text: opt[:label] },
          value: opt[:value]
        }
      end
    end
    private_class_method :next_update_options

    def self.actions_list_modal(incident)
      actions = incident.incident_actions.active.actions.recent
      blocks = action_items_blocks(actions, empty_label: "actions", button_label: "+ Add new action",
                                            button_action_id: Identifiers::ADD_NEW_ACTION,
                                            incident_id: incident.id)

      {
        type: "modal",
        callback_id: Identifiers::INCIDENT_ACTIONS_MODAL,
        private_metadata: incident.id,
        title: { type: "plain_text", text: "Actions" },
        close: { type: "plain_text", text: "Done" },
        blocks: blocks
      }
    end

    def self.followups_list_modal(incident)
      followups = incident.incident_actions.active.followups.recent
      blocks = action_items_blocks(followups, empty_label: "follow-ups", button_label: "+ Add new follow-up",
                                              button_action_id: Identifiers::ADD_NEW_FOLLOWUP,
                                              incident_id: incident.id)

      {
        type: "modal",
        callback_id: Identifiers::INCIDENT_FOLLOWUPS_MODAL,
        private_metadata: incident.id,
        title: { type: "plain_text", text: "Follow-ups" },
        close: { type: "plain_text", text: "Done" },
        blocks: blocks
      }
    end

    def self.create_action_modal(incident, private_metadata: nil)
      metadata = private_metadata || { incident_id: incident.id }.to_json
      parsed = JSON.parse(metadata) rescue {}
      initial_description = parsed["source_message_text"]

      description_element = {
        type: "plain_text_input",
        action_id: "description_input",
        multiline: true,
        placeholder: { type: "plain_text", text: "Write something" },
        max_length: 3000
      }
      description_element[:initial_value] = initial_description if initial_description.present?

      {
        type: "modal",
        callback_id: Identifiers::CREATE_ACTION_MODAL,
        private_metadata: metadata,
        title: { type: "plain_text", text: "Create action" },
        submit: { type: "plain_text", text: "Create" },
        close: { type: "plain_text", text: "Cancel" },
        blocks: [
          {
            type: "input",
            block_id: "description_block",
            element: description_element,
            label: { type: "plain_text", text: "Description" }
          },
          {
            type: "input",
            block_id: "assignee_block",
            element: {
              type: "users_select",
              action_id: "assignee_select",
              placeholder: { type: "plain_text", text: "Pick an option" }
            },
            label: { type: "plain_text", text: "Who's picking it up?" },
            optional: true
          },
          {
            type: "context",
            elements: [ { type: "mrkdwn", text: ":bulb: You can create an action from a Slack message by reacting with the :boom: emoji" } ]
          }
        ]
      }
    end

    def self.create_followup_modal(incident, private_metadata: nil)
      metadata = private_metadata || { incident_id: incident.id }.to_json
      parsed = JSON.parse(metadata) rescue {}
      initial_description = parsed["source_message_text"]

      description_element = {
        type: "plain_text_input",
        action_id: "description_input",
        multiline: true,
        placeholder: { type: "plain_text", text: "Write something" },
        max_length: 3000
      }
      description_element[:initial_value] = initial_description if initial_description.present?

      {
        type: "modal",
        callback_id: Identifiers::CREATE_FOLLOWUP_MODAL,
        private_metadata: metadata,
        title: { type: "plain_text", text: "Create follow-up" },
        submit: { type: "plain_text", text: "Create" },
        close: { type: "plain_text", text: "Cancel" },
        blocks: [
          {
            type: "input",
            block_id: "description_block",
            element: description_element,
            label: { type: "plain_text", text: "Description" }
          },
          {
            type: "input",
            block_id: "assignee_block",
            element: {
              type: "users_select",
              action_id: "assignee_select",
              placeholder: { type: "plain_text", text: "Pick an option" }
            },
            label: { type: "plain_text", text: "Who's picking it up?" },
            optional: true
          },
          {
            type: "context",
            elements: [ { type: "mrkdwn", text: ":bulb: You can create a follow-up from a Slack message by reacting with the :arrow_forward: emoji" } ]
          }
        ]
      }
    end

    def self.close_modal(incident, private_metadata: nil)
      metadata = private_metadata || incident.id
      workspace = incident.workspace

      name_value = incident.name.present? ? { initial_value: incident.name } : {}
      summary_value = incident.summary.present? ? { initial_value: incident.summary } : {}

      severities = workspace.incident_severities.active.ordered
      severity_options = severities.map do |severity|
        option = {
          text: { type: "plain_text", text: severity.name },
          value: severity.slug
        }
        option[:description] = { type: "plain_text", text: severity.description } if severity.description.present?
        option
      end
      initial_severity = severity_options.find { |o| o[:value] == incident.incident_severity.slug }

      lead_element = {
        type: "users_select",
        action_id: "lead_select",
        placeholder: { type: "plain_text", text: "Select a person" }
      }
      lead_element[:initial_user] = incident.lead.platform_user_id if incident.lead

      {
        type: "modal",
        callback_id: Identifiers::CLOSE_INCIDENT_MODAL,
        notify_on_close: true,
        private_metadata: metadata,
        title: { type: "plain_text", text: "Close incident" },
        submit: { type: "plain_text", text: "Close incident" },
        close: { type: "plain_text", text: "Cancel" },
        blocks: [
          {
            type: "input",
            block_id: "name_block",
            element: {
              type: "plain_text_input",
              action_id: "name_input",
              placeholder: { type: "plain_text", text: "Incident name" },
              max_length: 200
            }.merge(name_value),
            label: { type: "plain_text", text: "Incident name" },
            optional: true
          },
          {
            type: "input",
            block_id: "summary_block",
            element: {
              type: "plain_text_input",
              action_id: "summary_input",
              multiline: true,
              placeholder: { type: "plain_text", text: "Final summary of what happened and how it was resolved..." },
              max_length: 3000
            }.merge(summary_value),
            label: { type: "plain_text", text: "Summary" },
            optional: true
          },
          {
            type: "input",
            block_id: "severity_block",
            element: {
              type: "static_select",
              action_id: "severity_select",
              options: severity_options,
              initial_option: initial_severity
            }.compact,
            label: { type: "plain_text", text: "Severity" }
          },
          {
            type: "input",
            block_id: "lead_block",
            element: lead_element,
            label: { type: "plain_text", text: "Incident Lead" },
            optional: true
          }
        ]
      }
    end

    def self.link_incident_modal(incident, private_metadata: nil, default_type: IncidentRelationship::RELATED)
      metadata = private_metadata || incident.id
      workspace = incident.workspace

      other_incidents = workspace.incidents
        .where.not(id: incident.id)
        .recent
        .limit(100)

      incident_options = other_incidents.map do |inc|
        {
          text: { type: "plain_text", text: "#{inc.identifier}: #{(inc.name || 'Untitled').truncate(60)}" },
          value: inc.id
        }
      end

      return nil if incident_options.empty?

      {
        type: "modal",
        callback_id: Identifiers::LINK_INCIDENT_MODAL,
        private_metadata: metadata,
        title: { type: "plain_text", text: "Link incident" },
        submit: { type: "plain_text", text: "Link" },
        close: { type: "plain_text", text: "Cancel" },
        blocks: [
          {
            type: "section",
            text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" }
          },
          {
            type: "input",
            block_id: "relationship_type_block",
            element: {
              type: "static_select",
              action_id: "relationship_type_select",
              options: [
                {
                  text: { type: "plain_text", text: "Related" },
                  value: IncidentRelationship::RELATED,
                  description: { type: "plain_text", text: "Link as contextually related incidents" }
                },
                {
                  text: { type: "plain_text", text: "Duplicate (merge into target)" },
                  value: IncidentRelationship::DUPLICATE,
                  description: { type: "plain_text", text: "Mark this incident as a duplicate and cancel it" }
                }
              ],
              initial_option: default_type == IncidentRelationship::DUPLICATE ? {
                text: { type: "plain_text", text: "Duplicate (merge into target)" },
                value: IncidentRelationship::DUPLICATE,
                description: { type: "plain_text", text: "Mark this incident as a duplicate and cancel it" }
              } : {
                text: { type: "plain_text", text: "Related" },
                value: IncidentRelationship::RELATED,
                description: { type: "plain_text", text: "Link as contextually related incidents" }
              }
            },
            label: { type: "plain_text", text: "Relationship type" }
          },
          {
            type: "input",
            block_id: "target_incident_block",
            element: {
              type: "static_select",
              action_id: "target_incident_select",
              placeholder: { type: "plain_text", text: "Select an incident" },
              options: incident_options
            },
            label: { type: "plain_text", text: "Target incident" }
          }
        ]
      }
    end

    def self.reopen_modal(incident, private_metadata: nil)
      metadata = private_metadata || incident.id

      {
        type: "modal",
        callback_id: Identifiers::REOPEN_INCIDENT_MODAL,
        notify_on_close: true,
        private_metadata: metadata,
        title: { type: "plain_text", text: "Reopen incident" },
        submit: { type: "plain_text", text: "Reopen incident" },
        close: { type: "plain_text", text: "Cancel" },
        blocks: [
          {
            type: "section",
            text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" }
          },
          {
            type: "input",
            block_id: "reason_block",
            element: {
              type: "plain_text_input",
              action_id: "reason_input",
              multiline: true,
              placeholder: { type: "plain_text", text: "Why is this incident being reopened?" },
              max_length: 3000
            },
            label: { type: "plain_text", text: "Reason for reopening" },
            optional: true
          }
        ]
      }
    end

    def self.escalate_modal(incident, private_metadata: nil)
      metadata = private_metadata || incident.id

      {
        type: "modal",
        callback_id: Identifiers::ESCALATE_INCIDENT_MODAL,
        notify_on_close: true,
        private_metadata: metadata,
        title: { type: "plain_text", text: "Escalate incident" },
        submit: { type: "plain_text", text: "Escalate" },
        close: { type: "plain_text", text: "Cancel" },
        blocks: [
          {
            type: "section",
            text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" }
          },
          {
            type: "input",
            block_id: "escalate_to_block",
            element: {
              type: "users_select",
              action_id: "escalate_to_select",
              placeholder: { type: "plain_text", text: "Select a person" }
            },
            label: { type: "plain_text", text: "Who should we escalate to?" }
          },
          {
            type: "input",
            block_id: "reason_block",
            element: {
              type: "plain_text_input",
              action_id: "reason_input",
              multiline: true,
              placeholder: { type: "plain_text", text: "Add context for the escalation" },
              max_length: 3000
            },
            label: { type: "plain_text", text: "Reason" },
            optional: true
          }
        ]
      }
    end

    def self.invite_responders_modal(incident, selected_user_ids: [], private_metadata: nil)
      metadata = private_metadata || incident.id

      element = {
        type: "multi_users_select",
        action_id: "invite_users_select",
        placeholder: { type: "plain_text", text: "Select people to invite" }
      }
      element[:initial_users] = selected_user_ids if selected_user_ids.present?

      {
        type: "modal",
        callback_id: Identifiers::INVITE_RESPONDERS_MODAL,
        private_metadata: metadata,
        title: { type: "plain_text", text: "Invite responders" },
        submit: { type: "plain_text", text: "Invite" },
        close: { type: "plain_text", text: "Cancel" },
        blocks: [
          {
            type: "section",
            text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" }
          },
          {
            type: "input",
            block_id: "invite_users_block",
            element: element,
            label: { type: "plain_text", text: "Who should join this channel?" }
          }
        ]
      }
    end

    def self.action_items_blocks(items, empty_label:, button_label:, button_action_id:, incident_id:)
      blocks = []

      if items.any?
        open_items = items.reject(&:done?)
        done_items = items.select(&:done?)

        open_items.each_with_index do |item, idx|
          blocks << { type: "divider" } if idx > 0
          blocks.concat(action_list_item_blocks(item))
        end

        if done_items.any?
          blocks << { type: "divider" }
          blocks << {
            type: "context",
            elements: [ { type: "mrkdwn", text: ":white_check_mark: *#{done_items.size} completed*" } ]
          }
          done_items.each do |item|
            blocks << {
              type: "context",
              elements: [ { type: "mrkdwn", text: "~#{item.description.truncate(80)}~" } ]
            }
          end
        end

        blocks << { type: "divider" }
      else
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: "_No #{empty_label} yet. Click the button below to add one._" }
        }
      end

      blocks << {
        type: "actions",
        elements: [
          {
            type: "button",
            text: { type: "plain_text", text: button_label, emoji: true },
            action_id: button_action_id,
            value: incident_id
          }
        ]
      }

      blocks
    end
    private_class_method :action_items_blocks

    def self.action_list_item_blocks(action)
      status_icon = case action.status
      when IncidentAction::STATUS_OPEN then ":white_circle:"
      when IncidentAction::STATUS_IN_PROGRESS then ":large_blue_circle:"
      when IncidentAction::STATUS_DONE then ":white_check_mark:"
      end

      blocks = []

      blocks << {
        type: "section",
        text: { type: "mrkdwn", text: "#{status_icon}  *#{action.description}*" }
      }

      context_parts = []
      if action.assigned?
        context_parts << { type: "mrkdwn", text: "Assigned to <@#{action.assignee.platform_user_id}>" }
      else
        context_parts << { type: "mrkdwn", text: "Unassigned" }
      end

      status_label = case action.status
      when IncidentAction::STATUS_OPEN then "Open"
      when IncidentAction::STATUS_IN_PROGRESS then "In progress"
      end
      context_parts << { type: "mrkdwn", text: "  |  #{status_label}" } if status_label

      blocks << { type: "context", elements: context_parts }

      blocks
    end
    private_class_method :action_list_item_blocks

    def self.shoutout_modal(incident)
      {
        type: "modal",
        callback_id: Identifiers::SHOUTOUT_MODAL,
        private_metadata: { incident_id: incident.id }.to_json,
        title: {
          type: "plain_text",
          text: "Give a shoutout"
        },
        submit: {
          type: "plain_text",
          text: "Send"
        },
        close: {
          type: "plain_text",
          text: "Cancel"
        },
        blocks: [
          {
            type: "input",
            block_id: "recipient_block",
            element: {
              type: "users_select",
              action_id: "recipient_select",
              placeholder: {
                type: "plain_text",
                text: "Who deserves recognition?"
              }
            },
            label: {
              type: "plain_text",
              text: "Shoutout to"
            }
          },
          {
            type: "input",
            block_id: "message_block",
            element: {
              type: "plain_text_input",
              action_id: "message_input",
              multiline: true,
              placeholder: {
                type: "plain_text",
                text: "What did they do that was awesome?"
              },
              max_length: 500
            },
            label: {
              type: "plain_text",
              text: "Message"
            }
          }
        ]
      }
    end

    def self.home_command_help(command)
      COMMAND_HELP[command] || "_Select an action above to see how to use the command directly._"
    end

    COMMAND_HELP = {
      "new" => "*Create a new incident*\n\nUsage: `/ff new`\nOpens the incident creation form.",
      "summary" => "*Update incident summary*\n\nUsage: `/ff summary`\nUpdate the current understanding of the incident.",
      "lead" => "*Set incident lead*\n\nUsage: `/ff lead`\nAssign an incident lead to coordinate response.",
      "status" => "*Update status*\n\nUsage: `/ff status`\nChange the incident status (e.g., Investigating, Identified, Monitoring).",
      "severity" => "*Change severity*\n\nUsage: `/ff severity [critical|major|minor]`\nEscalate or de-escalate the incident severity.",
      "escalate" => "*Escalate to someone*\n\nUsage: `/ff escalate`\nPage or notify someone about this incident.",
      "invite" => "*Invite responders*\n\nUsage: `/ff invite @user1 @user2`\nInvites responders into the current incident channel. Run `/ff invite` without users to open a picker.",
      "actions" => "*Manage actions*\n\nUsage: `/ff actions`\nView, create, and complete incident action items.",
      "close" => "*Close incident*\n\nUsage: `/ff close` or `/ff resolve`\nMark the incident as resolved.",
      "postmortem" => "*Generate postmortem*\n\nUsage: `/ff postmortem`\nGenerate a postmortem document from the incident timeline.",
      "timeline" => "*View timeline*\n\nUsage: `/ff timeline`\nSee the full history of incident events.",
      "list" => "*List active incidents*\n\nUsage: `/ff list`\nShow all currently open incidents."
    }.freeze
  end
end
