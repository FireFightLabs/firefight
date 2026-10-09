module Slack
  module Messages
    module AgentReply
      def self.build(text:)
        Formatting.markdown_to_mrkdwn(text.to_s).truncate(Formatting::SECTION_TEXT_LIMIT).then do |body|
          [ { type: "section", text: { type: "mrkdwn", text: body } } ]
        end
      end
    end
  end
end
