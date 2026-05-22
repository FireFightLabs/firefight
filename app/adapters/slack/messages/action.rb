module Slack
  module Messages
    # Messages for incident action items (and their close cousins,
    # follow-ups). `created`, `picked_up`, and `completed` are the lifecycle
    # posts in the channel; `from_reaction` is the "would you like to create
    # an action from this message" prompt triggered by the :boom: /
    # :arrow_forward: reaction.
    module Action
      KIND_DISPLAY = {
        IncidentAction::ACTION_TYPE_FOLLOWUP => { emoji: ":arrow_forward:", label: "follow-up" },
        IncidentAction::ACTION_TYPE_ACTION   => { emoji: ":boom:",          label: "action" }
      }.freeze

      def self.created(action)
        emoji, label = display(action)
        creator = "<@#{action.created_by.platform_user_id}>"

        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{emoji}  *New #{label}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "> #{action.description}" } },
          {
            type: "context",
            elements: [
              { type: "mrkdwn", text: "Added by #{creator}  |  #{action.assigned? ? "Assigned to <@#{action.assignee.platform_user_id}>" : "Unassigned"}" }
            ]
          }
        ]

        button = if action.assigned?
          { text: ":white_check_mark: Mark as done", action_id: Identifiers::MARK_ACTION_DONE }
        else
          { text: ":raised_hands: I can take this", action_id: Identifiers::PICK_UP_ACTION }
        end

        blocks << {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: button[:text], emoji: true },
              action_id: button[:action_id],
              value: action.id
            }
          ]
        }
        blocks
      end

      def self.picked_up(action)
        emoji, label = display(action)

        [
          { type: "section", text: { type: "mrkdwn", text: "#{emoji}  *New #{label}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "> #{action.description}" } },
          {
            type: "context",
            elements: [ { type: "mrkdwn", text: ":large_blue_circle: Picked up by <@#{action.assignee.platform_user_id}>" } ]
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: ":white_check_mark: Mark as done", emoji: true },
                action_id: Identifiers::MARK_ACTION_DONE,
                value: action.id
              }
            ]
          }
        ]
      end

      def self.completed(action)
        emoji, _label = display(action)
        completer = action.assignee ? "<@#{action.assignee.platform_user_id}>" : "someone"

        [
          { type: "section", text: { type: "mrkdwn", text: "#{emoji}  ~#{action.description}~" } },
          { type: "context", elements: [ { type: "mrkdwn", text: ":white_check_mark: Completed by #{completer}" } ] }
        ]
      end

      def self.from_reaction(action_type, message_text, incident_id, source_message_link)
        cfg = KIND_DISPLAY.fetch(action_type) { KIND_DISPLAY[IncidentAction::ACTION_TYPE_ACTION] }
        button_action_id = action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? Identifiers::CREATE_FOLLOWUP_FROM_REACTION : Identifiers::CREATE_ACTION_FROM_REACTION

        button_value = {
          incident_id: incident_id,
          source_message_text: message_text.truncate(3000),
          source_message_link: source_message_link
        }.to_json

        [
          {
            type: "section",
            text: { type: "mrkdwn", text: "#{cfg[:emoji]} *Create #{cfg[:label]} from this message?*\n> #{message_text.truncate(200)}" }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: "Create #{cfg[:label]}", emoji: true },
                action_id: button_action_id,
                value: button_value,
                style: "primary"
              }
            ]
          }
        ]
      end

      def self.display(action)
        cfg = KIND_DISPLAY.fetch(action.action_type) { KIND_DISPLAY[IncidentAction::ACTION_TYPE_ACTION] }
        [ cfg[:emoji], cfg[:label] ]
      end
    end
  end
end
