module Slack
  module Messages
    # A change Halon was refused in a chat's thread because the person who asked holds no pack for it. It names the pack
    # and the admins, and carries Ask an admin, which only that person can use. Once asked it says when.
    module PackRefusal
      def self.build(refusal)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":lock:  *#{Mrkdwn.escape(refusal.headline)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(refusal.body) } }
        ]
        asked = refusal.asked_line
        return blocks << { type: "context", elements: [ { type: "mrkdwn", text: Mrkdwn.escape(asked) } ] } if asked

        blocks << { type: "actions", elements: [
          { type: "button", text: { type: "plain_text", text: "Ask an admin" }, action_id: Identifiers::PACK_REQUEST_ASK,
            value: refusal.pack_request_id, style: "primary" }
        ] }
      end

      def self.fallback(refusal) = "#{refusal.headline} #{refusal.body}"
    end
  end
end
