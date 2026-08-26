module Slack
  module Modals
    # The "View runbook" modal. Every step with its full instruction, plus a
    # person picker per step, which is where a lead hands work out rather than
    # reaching for a control on each row in the channel.
    module RunbookDetail
      # Three blocks per step against Slack's 100-block modal ceiling.
      MAX_STEPS = 45

      def self.build(incident_runbook)
        runbook = incident_runbook.runbook
        steps = runbook.runbook_steps.to_a
        actions = incident_runbook.actions_by_step

        {
          type: "modal",
          callback_id: Identifiers::RUNBOOK_DETAIL_MODAL,
          private_metadata: ModalState.encode(incident_id: incident_runbook.incident_id, incident_runbook_id: incident_runbook.id),
          title: { type: "plain_text", text: "Runbook" },
          close: { type: "plain_text", text: "Done" },
          blocks: blocks(runbook, steps, actions)
        }
      end

      def self.blocks(runbook, steps, actions)
        blocks = [ { type: "section", text: { type: "mrkdwn", text: "*#{runbook.name}*" } } ]

        if runbook.content.present?
          blocks << { type: "section", text: { type: "mrkdwn", text: runbook.content.truncate(3000) } }
        end

        steps.first(MAX_STEPS).each_with_index do |step, index|
          blocks << { type: "divider" }
          blocks.concat(step_blocks(step, index + 1, actions[step.id]))
        end

        if (remaining = steps.size - MAX_STEPS).positive?
          blocks << {
            type: "context",
            elements: [ { type: "mrkdwn", text: "#{remaining} more #{"step".pluralize(remaining)} not shown" } ]
          }
        end

        blocks
      end

      def self.step_blocks(step, position, action)
        text = "*#{position}. #{step.title}*"
        text += "\n#{step.instruction}" if step.instruction.present?

        section = {
          type: "section",
          block_id: "#{Identifiers::RUNBOOK_STEP_BLOCK_PREFIX}#{step.id}",
          text: { type: "mrkdwn", text: text.truncate(3000) }
        }
        if (element = picker(action))
          section[:accessory] = element
        end

        [ section, { type: "context", elements: [ { type: "mrkdwn", text: status_line(action) } ] } ]
      end

      def self.picker(action)
        return nil if action&.done?

        element = {
          type: "users_select",
          action_id: Identifiers::ASSIGN_RUNBOOK_STEP,
          placeholder: { type: "plain_text", text: "Assign" }
        }
        element[:initial_user] = action.assignee.platform_user_id if action&.assignee&.platform_user_id.present?
        element
      end

      def self.status_line(action)
        return ":white_check_mark: Completed by #{Slack::Mrkdwn.mention(action.assignee)}" if action&.done?
        return ":large_blue_circle: Claimed by #{Slack::Mrkdwn.mention(action.assignee)}" if action&.assigned?

        ":white_circle: Unclaimed"
      end
    end
  end
end
