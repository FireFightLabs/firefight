module Slack
  module Messages
    # A call Halon made in a chat that an approval rule held, once someone decided on it. Approving it never ran it, so
    # the message asks whoever asked to run it, with how things stand now. In the chat's thread it carries Run and
    # Dismiss, and Ask again once it expired. A chat on the dashboard is told by direct message, with a way to open it.
    module HeldCall
      TITLES = {
        Chat::HeldCall::STATUS_CHECKING => ":unlock:", Chat::HeldCall::STATUS_READY => ":unlock:",
        Chat::HeldCall::STATUS_RUNNING => ":arrows_counterclockwise:", Chat::HeldCall::STATUS_RAN => ":white_check_mark:",
        Chat::HeldCall::STATUS_FAILED => ":x:", Chat::HeldCall::STATUS_DISMISSED => ":leftwards_arrow_with_hook:",
        Chat::HeldCall::STATUS_DENIED => ":no_entry_sign:", Chat::HeldCall::STATUS_EXPIRED => ":hourglass:",
        Chat::HeldCall::STATUS_ASKED_AGAIN => ":hourglass:"
      }.freeze
      CHECKING = "_Halon is checking how things stand now. Run waits until it has._".freeze
      BUTTONS = {
        Chat::CurrentState::ACTION_RUN => [ "Run", Identifiers::HELD_CALL_RUN, "primary" ],
        Chat::CurrentState::ACTION_DISMISS => [ "Dismiss", Identifiers::HELD_CALL_DISMISS, nil ],
        Chat::CurrentState::ACTION_ASK_AGAIN => [ "Ask again", Identifiers::HELD_CALL_ASK_AGAIN, nil ]
      }.freeze
      ASKED_AGAIN = "Asked for approval again.".freeze

      # direct is a message to whoever asked rather than one in the chat's thread.
      def self.build(held_call, direct: false)
        blocks = [ { type: "section", text: { type: "mrkdwn", text: "#{TITLES.fetch(held_call.status, ':unlock:')}  *#{Mrkdwn.escape(held_call.headline)}*" } } ]
        body = body_text(held_call)
        blocks << { type: "divider" } if body || held_call.asked.any?
        blocks << { type: "section", text: { type: "mrkdwn", text: body.truncate(Formatting::SECTION_TEXT_LIMIT) } } if body
        if held_call.asked.any?
          fields = held_call.asked.map { |name, value| "#{Mrkdwn.escape(name)}: #{Mrkdwn.escape(value)}" }.join("  ·  ")
          blocks << { type: "context", elements: [ { type: "mrkdwn", text: fields.truncate(Formatting::SECTION_TEXT_LIMIT) } ] }
        end
        footer = footer_text(held_call)
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: footer } ] } if footer
        controls = direct ? link(held_call) : buttons(held_call)
        blocks << controls if controls
        blocks
      end

      def self.fallback(held_call) = held_call.headline

      def self.body_text(held_call)
        return CHECKING if held_call.status == Chat::HeldCall::STATUS_CHECKING

        lines = []
        lines << "*Now:* #{Mrkdwn.escape(held_call.state)}" if held_call.state && held_call.status == Chat::HeldCall::STATUS_READY
        lines << ":warning: #{Mrkdwn.escape(held_call.warning)}" if held_call.warning && held_call.status == Chat::HeldCall::STATUS_READY
        lines << "> #{Mrkdwn.escape(held_call.result).gsub("\n", "\n> ")}" if held_call.result.present?
        lines.join("\n").presence
      end

      def self.footer_text(held_call)
        parts = []
        if [ Chat::HeldCall::STATUS_CHECKING, Chat::HeldCall::STATUS_READY ].include?(held_call.status) && held_call.expires_at
          time = held_call.expires_at
          parts << "Expires #{Formatting.slack_time(time)}"
        end
        parts << "Run by #{Mrkdwn.escape(held_call.decided_by)}" if held_call.decided_by && ran?(held_call)
        parts << "Dismissed by #{Mrkdwn.escape(held_call.decided_by)}" if held_call.decided_by && held_call.status == Chat::HeldCall::STATUS_DISMISSED
        parts << ASKED_AGAIN if held_call.status == Chat::HeldCall::STATUS_ASKED_AGAIN
        parts.join("  ·  ").presence
      end

      def self.ran?(held_call)
        [ Chat::HeldCall::STATUS_RUNNING, Chat::HeldCall::STATUS_RAN, Chat::HeldCall::STATUS_FAILED ].include?(held_call.status)
      end

      # An actions block with no buttons is refused, so none is sent when nothing is offered. Slack cannot show a button
      # as blocked, so Run joins once Halon has checked, when the message is redrawn.
      def self.buttons(held_call)
        offers = held_call.offers
        offers -= [ Chat::CurrentState::ACTION_RUN ] if held_call.status == Chat::HeldCall::STATUS_CHECKING
        elements = offers.map do |offer|
          text, action_id, style = BUTTONS.fetch(offer)
          { type: "button", text: { type: "plain_text", text: text }, action_id: action_id, value: held_call.id, style: style }.compact
        end
        { type: "actions", elements: elements } if elements.any?
      end

      def self.link(held_call)
        url = DashboardUrl.agent_chat(held_call.conversation_id)
        return unless url

        { type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: "Open the chat" }, url: url } ] }
      end
    end
  end
end
