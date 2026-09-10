module Slack
  module Messages
    module Action
      KIND_DISPLAY = {
        IncidentAction::ACTION_TYPE_FOLLOWUP => { emoji: ":arrow_forward:", label: "follow-up" },
        IncidentAction::ACTION_TYPE_ACTION   => { emoji: ":boom:",          label: "action" }
      }.freeze

      def self.created(action)
        emoji, label = display(action)
        creator = Mrkdwn.mention(action.created_by)

        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{emoji}  *New #{label}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "> #{action.description}" } },
          {
            type: "context",
            elements: [
              { type: "mrkdwn", text: "Added by #{creator}  |  #{action.assigned? ? "Assigned to #{Mrkdwn.mention(action.assignee)}" : "Unassigned"}" }
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
            elements: [ { type: "mrkdwn", text: ":large_blue_circle: Picked up by #{Mrkdwn.mention(action.assignee)}" } ]
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
        picker[:initial_user] = action.assignee.platform_user_id if action.assignee&.platform_user_id.present?

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

      # Editing a message notifies nobody, so a handover posts. This one
      # becomes the item's own message when it has none yet.
      def self.handed_over(action, reassigned_by)
        emoji, label = display(action)

        notice(
          action,
          title: "#{emoji}  *#{Slack::Mrkdwn.mention(action.assignee)} now has this #{label}*",
          footer: "Handed over by #{Slack::Mrkdwn.mention(reassigned_by)}"
        ) + [ controls(action) ]
      end

      # Points at the item's existing message instead of carrying a second set
      # of controls nothing would keep up to date.
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

      # The link sits in the footer so it never competes with what was done.
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
        completer = Mrkdwn.mention(action.assignee)

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
