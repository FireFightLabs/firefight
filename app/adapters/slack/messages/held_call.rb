module Slack
  module Messages
    # A call Halon made in a chat that an approval rule held. In the chat's thread it is the request itself, a card saying
    # what Halon wants to do and who may approve it, with Approve and Deny for them. Approving runs it, and the same
    # message follows the run as a checklist (ChangeProgress), then says in one line how it went. A call approved before
    # approving ran it still offers Run and Dismiss, and Ask again once it expired. A chat on the dashboard is told by
    # direct message, with a way to open it. What the call was given is under Details (Modals::HeldCallDetails).
    module HeldCall
      ICONS = {
        Chat::HeldCall::STATUS_WAITING => ":raised_hand:", Chat::HeldCall::STATUS_CHECKING => ":raised_hand:", Chat::HeldCall::STATUS_READY => ":raised_hand:",
        Chat::HeldCall::STATUS_RAN => ":white_check_mark:", Chat::HeldCall::STATUS_FAILED => ":x:", Chat::HeldCall::STATUS_DISMISSED => ":leftwards_arrow_with_hook:",
        Chat::HeldCall::STATUS_DENIED => ":no_entry_sign:", Chat::HeldCall::STATUS_EXPIRED => ":hourglass:", Chat::HeldCall::STATUS_ASKED_AGAIN => ":hourglass:"
      }.freeze
      BUTTONS = {
        Chat::CurrentState::ACTION_RUN => [ "Run", Identifiers::HELD_CALL_RUN, "primary" ],
        Chat::CurrentState::ACTION_DISMISS => [ "Dismiss", Identifiers::HELD_CALL_DISMISS, nil ],
        Chat::CurrentState::ACTION_ASK_AGAIN => [ "Ask again", Identifiers::HELD_CALL_ASK_AGAIN, nil ]
      }.freeze
      APPROVE = "Approve".freeze
      DENY = "Deny".freeze
      DETAILS = "Details".freeze
      OPEN_CHAT = "Open the chat".freeze
      LINK_TEXT_LIMIT = 60

      # direct is a message to whoever asked rather than one in the chat's thread. rich is whether the workspace's Slack
      # shows card and plan blocks.
      def self.build(held_call, direct: false, rich: false)
        if held_call.status == Chat::HeldCall::STATUS_RUNNING
          footer = "Approved by #{Mrkdwn.escape(held_call.approved_by || 'someone')}"
          return ChangeProgress.blocks(title: held_call.action.upcase_first, work: held_call.progress, footer: footer, details: details_button(held_call), rich: rich)
        end

        controls = direct ? link_buttons(held_call) : buttons(held_call)
        blocks = Blocks::Card.new(icon: ICONS.fetch(held_call.status, ":raised_hand:"), title: Mrkdwn.escape(held_call.headline), body: body(held_call),
                                  actions: controls.first(Blocks::Card::ACTIONS_LIMIT)).to_blocks(rich: rich)
        rest = controls.drop(Blocks::Card::ACTIONS_LIMIT)
        rest.any? ? blocks + [ { type: "actions", elements: rest } ] : blocks
      end

      def self.fallback(held_call) = "#{held_call.headline}. #{held_call.line}"

      # The one line, with how things stand now while a call approved before approving ran it waits to be run, and the
      # page a finished change made.
      def self.body(held_call)
        lines = [ Mrkdwn.escape(held_call.line) ]
        if held_call.status == Chat::HeldCall::STATUS_READY
          lines << ":warning: #{Mrkdwn.escape(held_call.warning)}" if held_call.warning
          lines << "Now: #{Mrkdwn.escape(held_call.state)}" if held_call.state
          lines << "Expires #{Formatting.slack_time(held_call.expires_at)}" if held_call.expires_at
        end
        lines << link(held_call.link) if held_call.status == Chat::HeldCall::STATUS_RAN && held_call.link
        lines.compact.join("  ·  ")
      end

      # Approve and Deny while it waits, for its approvers, who are checked when they press. Run and Dismiss for a call
      # approved before approving ran it, Run only once Halon has checked, since Slack cannot show a button as blocked.
      def self.buttons(held_call)
        if held_call.status == Chat::HeldCall::STATUS_WAITING
          return [
            { type: "button", style: "primary", action_id: Identifiers::APPROVE_ABILITY, text: { type: "plain_text", text: APPROVE }, value: held_call.approval_id },
            { type: "button", style: "danger", action_id: Identifiers::DENY_ABILITY, text: { type: "plain_text", text: DENY }, value: held_call.approval_id },
            details_button(held_call)
          ]
        end

        offers = held_call.offers
        offers -= [ Chat::CurrentState::ACTION_RUN ] if held_call.status == Chat::HeldCall::STATUS_CHECKING
        offered = offers.map do |offer|
          text, action_id, style = BUTTONS.fetch(offer)
          { type: "button", text: { type: "plain_text", text: text }, action_id: action_id, value: held_call.id, style: style }.compact
        end
        offered + [ details_button(held_call) ]
      end

      def self.link_buttons(held_call)
        url = DashboardUrl.agent_chat(held_call.conversation_id)
        [ ({ type: "button", text: { type: "plain_text", text: OPEN_CHAT }, url: url } if url), details_button(held_call) ].compact
      end

      def self.details_button(held_call)
        { type: "button", text: { type: "plain_text", text: DETAILS }, action_id: Identifiers::HELD_CALL_DETAILS, value: held_call.id }
      end

      def self.link(url)
        shown = url.sub(%r{\Ahttps?://}, "").delete_suffix("/").truncate(LINK_TEXT_LIMIT)
        "<#{url}|#{Mrkdwn.escape(shown)}>"
      end
    end
  end
end
