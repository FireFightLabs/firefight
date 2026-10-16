module Slack
  module Messages
    # Halon's answer to /ff catchup. The answer is never cut short, it runs on into as many sections as it takes.
    module AiResponse
      HEADER_LIMIT = 150

      def self.build(incident:, answer:)
        title = "#{Slack::Emoji::HALON} #{incident.identifier} — #{incident.name || 'Untitled incident'}"
        blocks = [
          { type: "header", text: { type: "plain_text", text: title.truncate(HEADER_LIMIT), emoji: true } },
          { type: "divider" }
        ]

        Formatting.sections(Formatting.markdown_to_mrkdwn(answer.to_s)).each do |section|
          blocks << { type: "section", text: { type: "mrkdwn", text: section } }
        end

        blocks << { type: "divider" }
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: "Answered by Halon" } ] }
        blocks
      end
    end
  end
end
