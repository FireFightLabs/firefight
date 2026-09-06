module Slack
  module Messages
    # The onboarding checklist posted in #incidents. Rebuilt from the
    # onboarding stage on every update.
    module Welcome
      FALLBACK_TEXT = "Welcome to Firefight. Three steps to see how it works.".freeze

      DONE = ":white_check_mark:".freeze
      PENDING = ":white_circle:".freeze

      # The checklist ticks declared, led and resolved. Posting messages is
      # coached in the channel, not ticked here.
      STEP_STAGES = [
        WorkspaceOnboarding::STAGE_DECLARED,
        WorkspaceOnboarding::STAGE_LED,
        WorkspaceOnboarding::STAGE_RESOLVED
      ].freeze

      def self.build(stage)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":wave:  *Welcome to Firefight*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: body(stage) } }
        ]

        if stage < WorkspaceOnboarding::STAGE_DECLARED
          blocks << {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: "Declare a test incident", emoji: true },
                action_id: Identifiers::DECLARE_INCIDENT_FROM_WELCOME,
                style: "primary"
              }
            ]
          }
          blocks << { type: "context", elements: [ { type: "mrkdwn", text: "or run `/ff new` in any channel" } ] }
        end

        blocks << { type: "divider" }
        blocks << {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: "Share this channel", emoji: true },
              action_id: Identifiers::SHARE_INCIDENTS_CHANNEL
            },
            {
              type: "button",
              text: { type: "plain_text", text: "Preview an announcement", emoji: true },
              action_id: Identifiers::PREVIEW_ANNOUNCEMENT
            }
          ]
        }

        blocks
      end

      def self.body(stage)
        lines = [ "Three steps to see how it works. Takes about three minutes. The test incident is not counted in your metrics.", "" ]
        WorkspaceOnboarding::STEPS.each_with_index do |step, index|
          lines << "#{mark(stage >= STEP_STAGES[index])} *#{index + 1}. #{step[:title]}* #{step[:detail]}"
        end

        if stage == WorkspaceOnboarding::STAGE_DONE
          lines << ""
          lines << ":tada: That is the whole loop. Share this channel with your team so they can declare incidents too."
        end

        lines.join("\n")
      end

      def self.mark(done)
        done ? DONE : PENDING
      end
    end
  end
end
