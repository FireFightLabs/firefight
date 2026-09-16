module Slack
  module Messages
    module AgentReply
      SECTION_TEXT_LIMIT = 3000

      def self.build(text:)
        Formatting.markdown_to_mrkdwn(text.to_s).truncate(SECTION_TEXT_LIMIT).then do |body|
          [ { type: "section", text: { type: "mrkdwn", text: body } } ]
        end
      end
    end
  end
end
