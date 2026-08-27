module Slack
  module Modals
    # The "Actions" and "Follow-ups" list modals. Both render the same
    # list-of-items + add-button shape against the same `IncidentAction`
    # scope. Only the kind (action vs. follow-up) differs.
    module ActionItemsList
      KINDS = {
        action: {
          scope: :actions,
          title: "Actions",
          empty_label: "actions",
          button_label: "+ Add new action",
          button_action_id: -> { Identifiers::ADD_NEW_ACTION },
          callback_id: -> { Identifiers::INCIDENT_ACTIONS_MODAL }
        },
        followup: {
          scope: :followups,
          title: "Follow-ups",
          empty_label: "follow-ups",
          button_label: "+ Add new follow-up",
          button_action_id: -> { Identifiers::ADD_NEW_FOLLOWUP },
          callback_id: -> { Identifiers::INCIDENT_FOLLOWUPS_MODAL }
        }
      }.freeze

      # An open item costs four blocks (divider, text, status, controls) and a
      # completed one costs a line, against Slack's 100-block modal ceiling.
      MAX_OPEN_ITEMS = 20
      MAX_DONE_ITEMS = 10

      def self.build(incident, kind:)
        cfg = KINDS.fetch(kind)
        items = incident.incident_actions.active.public_send(cfg[:scope]).recent

        {
          type: "modal",
          callback_id: cfg[:callback_id].call,
          private_metadata: ModalState.encode(incident_id: incident.id),
          title: { type: "plain_text", text: cfg[:title] },
          close: { type: "plain_text", text: "Done" },
          blocks: list_blocks(items, cfg, incident.id)
        }
      end

      def self.list_blocks(items, cfg, incident_id)
        blocks = []

        if items.any?
          open_items, done_items = items.partition { |i| !i.done? }
          open_items.first(MAX_OPEN_ITEMS).each_with_index do |item, idx|
            blocks << { type: "divider" } if idx > 0
            blocks.concat(item_blocks(item))
          end

          if (hidden = open_items.size - MAX_OPEN_ITEMS).positive?
            blocks << { type: "context", elements: [ { type: "mrkdwn", text: "#{hidden} more open, worked from the channel" } ] }
          end

          if done_items.any?
            blocks << { type: "divider" }
            blocks << { type: "context", elements: [ { type: "mrkdwn", text: ":white_check_mark: *#{done_items.size} completed*" } ] }
            done_items.first(MAX_DONE_ITEMS).each do |item|
              blocks << { type: "context", elements: [ { type: "mrkdwn", text: "~#{item.description.truncate(80)}~" } ] }
            end
          end

          blocks << { type: "divider" }
        else
          blocks << { type: "section", text: { type: "mrkdwn", text: "_No #{cfg[:empty_label]} yet. Click the button below to add one._" } }
        end

        blocks << {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: cfg[:button_label], emoji: true },
              action_id: cfg[:button_action_id].call,
              value: incident_id
            }
          ]
        }

        blocks
      end

      STATUS_ICON = {
        IncidentAction::STATUS_OPEN => ":white_circle:",
        IncidentAction::STATUS_IN_PROGRESS => ":large_blue_circle:",
        IncidentAction::STATUS_DONE => ":white_check_mark:"
      }.freeze

      STATUS_LABEL = {
        IncidentAction::STATUS_OPEN => "Open",
        IncidentAction::STATUS_IN_PROGRESS => "In progress"
      }.freeze

      def self.item_blocks(action)
        context_parts = [
          { type: "mrkdwn", text: action.assigned? ? "Assigned to #{Slack::Mrkdwn.mention(action.assignee)}" : "Unassigned" }
        ]
        if (status_label = STATUS_LABEL[action.status])
          context_parts << { type: "mrkdwn", text: "  |  #{status_label}" }
        end

        [
          { type: "section", text: { type: "mrkdwn", text: "#{STATUS_ICON[action.status]}  *#{action.description}*" } },
          { type: "context", elements: context_parts },
          Slack::Messages::Action.controls(action)
        ]
      end
    end
  end
end
