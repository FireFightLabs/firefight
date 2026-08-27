module Slack
  module Messages
    module AiResponse
      SECTION_TEXT_LIMIT = 3000

      def self.build(incident:, answer:)
        blocks = [
          {
            type: "header",
            text: { type: "plain_text", text: ":fire: #{incident.identifier} — #{incident.name || 'Untitled Incident'}", emoji: true }
          },
          { type: "divider" }
        ]

        Formatting.markdown_to_mrkdwn(answer.to_s).split("\n\n").each do |paragraph|
          stripped = paragraph.strip
          next if stripped.empty?

          blocks << {
            type: "section",
            text: { type: "mrkdwn", text: stripped[0, SECTION_TEXT_LIMIT] }
          }
        end

        blocks << { type: "divider" }
        blocks << {
          type: "context",
          elements: [ { type: "mrkdwn", text: ":sparkles: _Powered by Firefight AI_" } ]
        }
        blocks
      end
    end
  end
end
