module Slack
  module Messages
    module Welcome
      FALLBACK_TEXT = "Welcome to Firefight. Three steps to see how it works.".freeze

      # A finished step trades its number for a check, the way the setup checklist marks one.
      DONE = ":white_check_mark:".freeze

      # Posting messages is coached in the channel, not ticked here.
      STEP_STAGES = [
        WorkspaceOnboarding::STAGE_DECLARED,
        WorkspaceOnboarding::STAGE_LED,
        WorkspaceOnboarding::STAGE_RESOLVED
      ].freeze

      def self.build(stage)
        declaring = stage < WorkspaceOnboarding::STAGE_DECLARED
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":wave:  *Welcome to Firefight*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: body(stage) } },
          { type: "actions", elements: buttons(declaring) }
        ]
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: "Or run `/ff new` in any channel." } ] } if declaring
        blocks
      end

      def self.buttons(declaring)
        elements = []
        if declaring
          elements << {
            type: "button",
            text: { type: "plain_text", text: "Declare a test incident", emoji: true },
            action_id: Identifiers::DECLARE_INCIDENT_FROM_WELCOME,
            style: "primary"
          }
        end
        elements << {
          type: "button",
          text: { type: "plain_text", text: "Share this channel", emoji: true },
          action_id: Identifiers::SHARE_INCIDENTS_CHANNEL
        }
        elements << {
          type: "button",
          text: { type: "plain_text", text: "Preview an announcement", emoji: true },
          action_id: Identifiers::PREVIEW_ANNOUNCEMENT
        }
      end

      def self.body(stage)
        lines = [ "Three steps to see how it works. Takes about three minutes. The test incident is not counted in your metrics.", "" ]
        WorkspaceOnboarding::STEPS.each_with_index do |step, index|
          lines << "#{marker(stage >= STEP_STAGES[index], index)} *#{step[:title]}* #{step[:detail]}"
        end

        if stage == WorkspaceOnboarding::STAGE_DONE
          lines << ""
          lines << ":tada: That is the whole loop. Share this channel with your team so they can declare incidents too."
        end

        lines.join("\n")
      end

      def self.marker(done, index)
        done ? DONE : "#{index + 1}."
      end
    end
  end
end
