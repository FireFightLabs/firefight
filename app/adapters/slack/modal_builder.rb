module Slack
  # Builds Slack Block Kit modal views
  class ModalBuilder
    # Build incident creation modal
    #
    # @return [Hash] Block Kit modal view JSON
    def self.incident_creation_form
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
              text: "Incident name (optional)"
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
            element: {
              type: "static_select",
              action_id: "severity_select",
              placeholder: {
                type: "plain_text",
                text: "Select severity"
              },
              options: [
                {
                  text: {
                    type: "plain_text",
                    text: "Critical"
                  },
                  value: "critical"
                },
                {
                  text: {
                    type: "plain_text",
                    text: "Major"
                  },
                  value: "major"
                },
                {
                  text: {
                    type: "plain_text",
                    text: "Minor"
                  },
                  value: "minor"
                }
              ],
              initial_option: {
                text: {
                  type: "plain_text",
                  text: "Minor"
                },
                value: "minor"
              }
            },
            label: {
              type: "plain_text",
              text: "Severity"
            },
            hint: {
              type: "plain_text",
              text: "Issues with low impact, which can usually be handled within working hours. Most customers are unlikely to notice any problems. Examples include a slight drop in application performance."
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
                text: "Think about what you'd like to read if you were coming to the incident fresh..."
              },
              max_length: 3000
            },
            label: {
              type: "plain_text",
              text: "Summary (optional)"
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
                  value: "public"
                },
                {
                  text: { type: "plain_text", text: "Private" },
                  value: "private"
                }
              ],
              initial_option: {
                text: { type: "plain_text", text: "Everyone (public)" },
                value: "public"
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
    def self.home_modal
      {
        type: "modal",
        callback_id: Identifiers::INCIDENT_HOME_MODAL,
        title: {
          type: "plain_text",
          text: "Incident Home"
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
              text: "*I want to...*"
            }
          },
          {
            type: "input",
            dispatch_action: true,
            block_id: "action_select_block",
            element: {
              type: "static_select",
              action_id: Identifiers::HOME_ACTION_SELECT,
              placeholder: {
                type: "plain_text",
                text: "Select an action"
              },
              options: home_modal_options
            },
            label: {
              type: "plain_text",
              text: "Choose an action"
            }
          },
          {
            type: "section",
            block_id: "command_details_block",
            text: {
              type: "mrkdwn",
              text: "_Select an action above to see how to use the command directly._"
            }
          }
        ]
      }
    end

    def self.home_modal_options
      [
        { text: { type: "plain_text", text: "Create a new incident" }, value: "new", description: { type: "plain_text", text: "/ff new" } },
        { text: { type: "plain_text", text: "Update incident summary" }, value: "summary", description: { type: "plain_text", text: "/ff summary" } },
        { text: { type: "plain_text", text: "Set incident lead" }, value: "lead", description: { type: "plain_text", text: "/ff lead" } },
        { text: { type: "plain_text", text: "Update status" }, value: "status", description: { type: "plain_text", text: "/ff status" } },
        { text: { type: "plain_text", text: "Change severity" }, value: "severity", description: { type: "plain_text", text: "/ff severity" } },
        { text: { type: "plain_text", text: "Escalate to someone" }, value: "escalate", description: { type: "plain_text", text: "/ff escalate" } },
        { text: { type: "plain_text", text: "Manage actions" }, value: "actions", description: { type: "plain_text", text: "/ff actions" } },
        { text: { type: "plain_text", text: "Close incident" }, value: "close", description: { type: "plain_text", text: "/ff close" } },
        { text: { type: "plain_text", text: "Generate postmortem" }, value: "postmortem", description: { type: "plain_text", text: "/ff postmortem" } },
        { text: { type: "plain_text", text: "View timeline" }, value: "timeline", description: { type: "plain_text", text: "/ff timeline" } },
        { text: { type: "plain_text", text: "List active incidents" }, value: "list", description: { type: "plain_text", text: "/ff list" } }
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
      "actions" => "*Manage actions*\n\nUsage: `/ff actions`\nView, create, and complete incident action items.",
      "close" => "*Close incident*\n\nUsage: `/ff close` or `/ff resolve`\nMark the incident as resolved.",
      "postmortem" => "*Generate postmortem*\n\nUsage: `/ff postmortem`\nGenerate a postmortem document from the incident timeline.",
      "timeline" => "*View timeline*\n\nUsage: `/ff timeline`\nSee the full history of incident events.",
      "list" => "*List active incidents*\n\nUsage: `/ff list`\nShow all currently open incidents."
    }.freeze
  end
end
