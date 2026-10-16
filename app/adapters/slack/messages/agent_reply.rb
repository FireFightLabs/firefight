module Slack
  module Messages
    # Halon's reply in a thread, as many sections as it takes. A reply is never cut short, and one longer than a message
    # holds runs on into further messages (Formatting.message_parts).
    module AgentReply
      def self.build(text:)
        Formatting.sections(Formatting.markdown_to_mrkdwn(text.to_s)).map { |section| { type: "section", text: { type: "mrkdwn", text: section } } }
      end
    end
  end
end
