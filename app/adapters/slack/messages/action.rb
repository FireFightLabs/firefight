module Slack
  module Messages
    # Messages for incident action items (and their close cousins,
    # follow-ups). `created`, `picked_up`, and `completed` are the lifecycle
    # posts in the channel. `from_reaction` is the "would you like to create
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

        blocks << controls(action)
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
          controls(action)
        ]
      end

      def self.controls(action)
        button = if action.assigned?
          { text: ":white_check_mark: Mark as done", action_id: Identifiers::MARK_ACTION_DONE }
        else
          { text: ":raised_hands: I can take this", action_id: Identifiers::PICK_UP_ACTION }
        end

        picker = {
          type: "users_select",
          action_id: Identifiers::REASSIGN_ACTION,
          placeholder: { type: "plain_text", text: action.assigned? ? "Reassign" : "Assign to" }
        }
        picker[:initial_user] = action.assignee.platform_user_id if action.assigned?

        {
          type: "actions",
          block_id: "#{Identifiers::ACTION_BLOCK_PREFIX}#{action.id}",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: button[:text], emoji: true },
              action_id: button[:action_id],
              value: action.id
            },
            picker
          ]
        }
      end

      # Editing a message notifies nobody, so a handover has to post. This one
      # carries the controls and becomes the item's own message, for an item
      # that has none yet.
      def self.handed_over(action, reassigned_by)
        emoji, label = display(action)

        notice(
          action,
          title: "#{emoji}  *#{Slack::Mrkdwn.mention(action.assignee)} now has this #{label}*",
          footer: "Handed over by #{Slack::Mrkdwn.mention(reassigned_by)}"
        ) + [ controls(action) ]
      end

      # The same handover for an item that already has a message. It points at
      # that one rather than carrying a second set of controls that nothing
      # would keep up to date.
      def self.handover_notice(action, reassigned_by, link: nil)
        emoji, label = display(action)

        notice(
          action,
          title: "#{emoji}  *#{Slack::Mrkdwn.mention(action.assignee)} now has this #{label}*",
          footer: "Handed over by #{Slack::Mrkdwn.mention(reassigned_by)}",
          link: link
        )
      end

      def self.completed_notice(action, completed_by, link: nil)
        _emoji, label = display(action)

        notice(
          action,
          title: ":white_check_mark:  *#{label.capitalize} completed*",
          footer: "Completed by #{Slack::Mrkdwn.mention(completed_by)}",
          link: link
        )
      end

      # Something happened to an item and the channel has moved on. Title, what
      # it was, then attribution, with the link demoted to the footer so it
      # never competes with what was done.
      def self.notice(action, title:, footer:, link: nil)
        footer += "  ·  <#{link.url}|#{link.label}>" if link

        [
          { type: "section", text: { type: "mrkdwn", text: title } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "> #{action.description}" } },
          { type: "context", elements: [ { type: "mrkdwn", text: footer } ] }
        ]
      end

      def self.label_for(action)
        display(action).last
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
