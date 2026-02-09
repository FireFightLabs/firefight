module Slack
  # Builds Slack Block Kit modal views
  class ModalBuilder
    # Build incident creation modal
    #
    # @return [Hash] Block Kit modal view JSON
    def self.incident_creation_form
      {
        type: "modal",
        callback_id: Slack::Identifiers::INCIDENT_CREATION_MODAL,
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
  end
end
