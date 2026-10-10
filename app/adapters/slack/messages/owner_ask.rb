module Slack
  module Messages
    # Asks whoever started something whether Halon may stop it, in their direct messages, with Agree and Say no until they
    # answer, and then what they said.
    module OwnerAsk
      def self.build(ask)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":raised_hand:  *#{Mrkdwn.escape(ask.headline)}*" } }
        ]
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: "Why: #{Mrkdwn.escape(ask.reason)}".truncate(2_000) } ] } if ask.reason.present?
        if ask.answered_words
          blocks << { type: "context", elements: [ { type: "mrkdwn", text: Mrkdwn.escape(ask.answered_words) } ] }
          return blocks
        end

        blocks << { type: "section", text: { type: "mrkdwn", text: "It runs only once you agree. Is that all right?" } }
        blocks << { type: "actions", elements: [
          { type: "button", style: "primary", text: { type: "plain_text", text: "Agree" }, action_id: Identifiers::OWNER_AGREE, value: ask.id.to_s },
          { type: "button", text: { type: "plain_text", text: "Say no" }, action_id: Identifiers::OWNER_DECLINE, value: ask.id.to_s }
        ] }
        blocks
      end

      def self.fallback(ask) = ask.headline
    end
  end
end
