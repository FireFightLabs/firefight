module Slack
  module Messages
    # The message pinned to the top of #incidents on install. It is the
    # onboarding: three steps, ticked off in place as the first incident moves
    # through them. Rebuilt from WorkspaceOnboarding::Progress each time, so
    # the message never says more than the incident record does.
    module Welcome
      FALLBACK_TEXT = "Welcome to Firefight. Three steps to see how it works.".freeze

      DONE = ":white_check_mark:".freeze
      PENDING = ":white_circle:".freeze

      def self.build(progress)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":wave:  *Welcome to Firefight*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: body(progress) } }
        ]

        unless progress.declared
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

      def self.body(progress)
        done = [ progress.declared, progress.lead_set, progress.resolved ]
        lines = [ "Three steps to see how it works. Takes about three minutes with a test incident that stays out of your numbers.", "" ]
        WorkspaceOnboarding::STEPS.each_with_index do |step, index|
          lines << "#{mark(done[index])} *#{index + 1}. #{step[:title]}* #{step[:detail]}"
        end

        if progress.complete?
          lines << ""
          lines << ":tada: You have seen the whole loop. Settings in the dashboard shape it to your team."
        end

        lines.join("\n")
      end

      def self.mark(done)
        done ? DONE : PENDING
      end
    end
  end
end
