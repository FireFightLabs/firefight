module Slack
  module Messages
    # A secret a tool call in a chat's thread handed to the person who asked, either a value to type, or a credential to reveal.
    # Neither happens in Slack, so the message says what it is and links to the chat in Firefight, where the card is.
    module SecretEntry
      def self.build(entry)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":key:  *#{Mrkdwn.escape(entry.headline)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(where(entry)) } }
        ]
        status = entry.status_line
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: Mrkdwn.escape(status) } ] } if status
        url = DashboardUrl.agent_chat(entry.conversation.id)
        blocks << { type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: label(entry) }, url: url } ] } if url && entry.open?
        blocks
      end

      def self.fallback(entry) = "#{entry.headline}. #{where(entry)}"

      def self.where(entry)
        doing = entry.enter? ? "types the value" : "reveals it"
        "#{entry.requester_name} #{doing} in this chat in Firefight, so it never passes through Slack or Halon."
      end

      def self.label(entry) = entry.enter? ? "Enter the value in Firefight" : "Reveal in Firefight"
    end
  end
end
