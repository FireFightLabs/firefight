module Slack
  module Messages
    # The copy of a refusal a person keeps in their direct messages: why, then where they asked.
    module Refusal
      def self.build(text, channel_id:)
        [
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(text) } },
          { type: "context", elements: [ { type: "mrkdwn", text: "About what you asked in <##{channel_id}>" } ] }
        ]
      end
    end
  end
end
