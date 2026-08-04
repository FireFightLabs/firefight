module Slack
  module Messages
    # Channel message posted when a runbook is attached to an incident.
    # `attached` is the interactive state (numbered steps + an "add steps as
    # actions" button); `applied` replaces the button with a context line once
    # the steps have been turned into action items.
    module Runbook
      MAX_STEPS = 10

      def self.attached(incident_runbook)
        runbook = incident_runbook.runbook
        blocks = header_blocks(runbook)

        if (button = apply_button(incident_runbook))
          blocks << button
        end

        blocks
      end

      def self.applied(incident_runbook)
        runbook = incident_runbook.runbook
        count = runbook.runbook_steps.size
        blocks = header_blocks(runbook)
        blocks << {
          type: "context",
          elements: [ { type: "mrkdwn", text: ":white_check_mark: #{count} #{"action".pluralize(count)} created" } ]
        }
        blocks
      end

      def self.header_blocks(runbook)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":book:  *Runbook attached: #{runbook.name}*" } },
          { type: "divider" }
        ]

        if runbook.summary.present?
          blocks << { type: "section", text: { type: "mrkdwn", text: runbook.summary } }
        end

        steps = runbook.runbook_steps.to_a
        if steps.any?
          blocks << { type: "section", text: { type: "mrkdwn", text: steps_text(steps) } }
        end

        if runbook.external_url.present?
          blocks << {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: "Open runbook", emoji: true },
                url: runbook.external_url
              }
            ]
          }
        end

        blocks
      end

      def self.steps_text(steps)
        lines = steps.first(MAX_STEPS).each_with_index.map { |step, idx| "#{idx + 1}. #{step.title}" }
        remaining = steps.size - MAX_STEPS
        lines << "+#{remaining} more" if remaining.positive?
        lines.join("\n")
      end

      def self.apply_button(incident_runbook)
        return nil if incident_runbook.applied?
        return nil if incident_runbook.runbook.runbook_steps.empty?

        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: ":clipboard: Add steps as actions", emoji: true },
              action_id: Identifiers::APPLY_RUNBOOK,
              value: incident_runbook.id,
              style: "primary"
            }
          ]
        }
      end
    end
  end
end
