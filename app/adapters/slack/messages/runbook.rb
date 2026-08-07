module Slack
  module Messages
    # Channel message posted when a runbook is attached to an incident. Every
    # step is a row carrying its own button, and the message is updated in
    # place as rows are claimed and completed, so working a runbook never posts
    # anything else into the channel.
    module Runbook
      # Slack caps a message at 50 blocks, four of which are header and footer.
      MAX_STEP_ROWS = 45

      def self.attached(incident_runbook)
        runbook = incident_runbook.runbook
        steps = runbook.runbook_steps.to_a
        actions = actions_by_step(incident_runbook)

        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":book:  *Runbook attached: #{runbook.name}*" } },
          { type: "divider" }
        ]

        if runbook.summary.present?
          blocks << { type: "section", text: { type: "mrkdwn", text: runbook.summary } }
        end

        steps.first(MAX_STEP_ROWS).each_with_index do |step, index|
          blocks << step_row(incident_runbook, step, index + 1, actions[step.id])
        end

        if (remaining = steps.size - MAX_STEP_ROWS).positive?
          blocks << {
            type: "context",
            elements: [ { type: "mrkdwn", text: "#{remaining} more #{"step".pluralize(remaining)} in the runbook" } ]
          }
        end

        blocks << footer(incident_runbook, steps)
        blocks.compact
      end

      def self.step_row(incident_runbook, step, position, action)
        row = {
          type: "section",
          block_id: "#{Identifiers::RUNBOOK_STEP_BLOCK_PREFIX}#{step.id}",
          text: { type: "mrkdwn", text: step_text(step, position, action) }
        }
        if (accessory = step_accessory(incident_runbook, step, action))
          row[:accessory] = accessory
        end
        row
      end

      def self.step_text(step, position, action)
        return "*#{position}.* ~#{step.title}~\n_:white_check_mark: Completed by #{mention(action.assignee)}_" if action&.done?
        return "*#{position}.* #{step.title}\n_Claimed by #{mention(action.assignee)}_" if action&.assigned?

        "*#{position}.* #{step.title}"
      end

      def self.step_accessory(incident_runbook, step, action)
        return nil if action&.done?

        if action&.assigned?
          {
            type: "button",
            text: { type: "plain_text", text: ":white_check_mark: Mark as done", emoji: true },
            action_id: Identifiers::MARK_ACTION_DONE,
            value: action.id
          }
        else
          {
            type: "button",
            text: { type: "plain_text", text: ":raised_hands: I can take this", emoji: true },
            action_id: Identifiers::CLAIM_RUNBOOK_STEP,
            value: { incident_runbook_id: incident_runbook.id, step_id: step.id }.to_json
          }
        end
      end

      def self.footer(incident_runbook, steps)
        elements = []

        if steps.any?
          elements << {
            type: "button",
            text: { type: "plain_text", text: ":book: View runbook", emoji: true },
            action_id: Identifiers::VIEW_RUNBOOK,
            value: incident_runbook.id
          }
        end

        if incident_runbook.runbook.external_url.present?
          elements << {
            type: "button",
            text: { type: "plain_text", text: "Open runbook", emoji: true },
            url: incident_runbook.runbook.external_url
          }
        end

        return nil if elements.empty?

        { type: "actions", elements: elements }
      end

      def self.actions_by_step(incident_runbook)
        incident_runbook.incident.incident_actions.active
          .where.not(runbook_step_id: nil)
          .includes(:assignee)
          .index_by(&:runbook_step_id)
      end

      def self.mention(membership)
        membership ? "<@#{membership.platform_user_id}>" : "someone"
      end
    end
  end
end
