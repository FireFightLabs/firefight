module Slack
  module Messages
    # Posted once, in the channel of a workspace's first incident, under the
    # quick actions. Hands the responder the three things that turn a test
    # into a real demo, including messages to paste so the write-up has
    # something to draw from.
    module FirstIncidentWalkthrough
      FALLBACK_TEXT = "Your first incident, so here is the walkthrough.".freeze

      SCRIPT = [
        "Customers are seeing 502s on checkout since 14:05.",
        "Rolled back the 14:00 deploy of payments-api.",
        "Errors stopped, checkout is healthy again."
      ].freeze

      def self.build(incident)
        [
          { type: "section", text: { type: "mrkdwn", text: ":compass:  *Your first incident, so here is the walkthrough*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: body(incident) } },
          { type: "context", elements: [ { type: "mrkdwn", text: "This message only appears on your first incident." } ] }
        ]
      end

      def self.body(incident)
        [
          "1. Click *Make me Lead* above. The announcement in #{announcements_channel(incident)} updates as you go.",
          "2. Post a few messages about what is happening. The write-up is built from them. Paste these if you like:",
          "```",
          *SCRIPT,
          "```",
          "3. Run `/ff resolve` when it is fixed."
        ].join("\n")
      end

      def self.announcements_channel(incident)
        channel_id = incident.workspace.incidents_channel_id
        channel_id.present? ? "<##{channel_id}>" : "#incidents"
      end
    end
  end
end
