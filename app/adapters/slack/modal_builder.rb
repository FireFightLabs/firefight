module Slack
  # Builds Slack Block Kit modal views
  class ModalBuilder
    # Build incident creation modal
    #
    # @return [Hash] Block Kit modal view JSON
    def self.incident_creation_form
      {
        type: "modal",
        callback_id: "incident_creation_modal",
        title: {
          type: "plain_text",
          text: "Create Incident"
        },
        submit: {
          type: "plain_text",
          text: "Create"
        },
        close: {
          type: "plain_text",
          text: "Cancel"
        },
        blocks: [
          {
            type: "input",
            block_id: "title_block",
            element: {
              type: "plain_text_input",
              action_id: "title_input",
              placeholder: {
                type: "plain_text",
                text: "Brief description of the incident"
              },
              max_length: 200
            },
            label: {
              type: "plain_text",
              text: "Incident Title"
            }
          },
          {
            type: "input",
            block_id: "description_block",
            element: {
              type: "plain_text_input",
              action_id: "description_input",
              multiline: true,
              placeholder: {
                type: "plain_text",
                text: "What's happening? Include any relevant details..."
              },
              max_length: 3000
            },
            label: {
              type: "plain_text",
              text: "Description"
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
                    text: "🔴 Critical - System down, major impact"
                  },
                  value: "critical"
                },
                {
                  text: {
                    type: "plain_text",
                    text: "🟠 High - Significant degradation"
                  },
                  value: "high"
                },
                {
                  text: {
                    type: "plain_text",
                    text: "🟡 Medium - Minor issues, workaround available"
                  },
                  value: "medium"
                },
                {
                  text: {
                    type: "plain_text",
                    text: "🟢 Low - Minimal impact"
                  },
                  value: "low"
                }
              ],
              initial_option: {
                text: {
                  type: "plain_text",
                  text: "🟠 High - Significant degradation"
                },
                value: "high"
              }
            },
            label: {
              type: "plain_text",
              text: "Severity"
            }
          }
        ]
      }
    end
  end
end
