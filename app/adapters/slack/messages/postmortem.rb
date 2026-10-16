module Slack
  module Messages
    module Postmortem
      def self.build(incident, postmortem)
        duration_text = Formatting.format_duration(incident.time_to_resolve)
        lead_text = incident.lead ? Mrkdwn.mention(incident.lead) : "Unassigned"

        title_line = "*#{postmortem.title}*"
        meta_line  = [ "Duration: #{duration_text}", "Severity: #{incident.incident_severity.name}", "Lead: #{lead_text}" ].join(Formatting::SEPARATOR)

        blocks = [
          { type: "header", text: { type: "plain_text", text: "#{Slack::Emoji::POSTMORTEM} Postmortem — #{incident.identifier}", emoji: true } },
          { type: "section", text: { type: "mrkdwn", text: "#{title_line}\n#{meta_line}" } }
        ]

        url = Slack::DashboardUrl.postmortem(incident)
        if url
          blocks << {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: "View full postmortem", emoji: true },
                url: url,
                style: "primary"
              }
            ]
          }
        end

        blocks << {
          type: "context",
          elements: [ { type: "mrkdwn", text: "#{Slack::Emoji::HALON} _Drafted by Halon_" } ]
        }

        blocks
      end
    end
  end
end
