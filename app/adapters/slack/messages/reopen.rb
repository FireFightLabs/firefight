module Slack
  module Messages
    module Reopen
      def self.build(incident, reopened_by_platform_user_id:, reopened_by_name: nil, reason: nil)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":rotating_light:  *Incident Reopened*" } },
          { type: "divider" }
        ]
        blocks.concat(Formatting.quoted_blocks(reason))
        blocks << {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "Reopened by #{Mrkdwn.person(reopened_by_platform_user_id, reopened_by_name)}  |  Status: #{incident.incident_status.name}" }
          ]
        }
        blocks
      end

      def self.announcement_thread(incident, reopened_by_platform_user_id:, reopened_by_name: nil, reason: nil)
        blocks = [
          { type: "header", text: { type: "plain_text", text: "Incident Reopened", emoji: true } },
          { type: "divider" }
        ]
        blocks.concat(Formatting.quoted_blocks(reason))
        blocks << { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: Reopened by: #{Mrkdwn.person(reopened_by_platform_user_id, reopened_by_name, bold: true)}" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":bar_chart: Status: *#{incident.incident_status.name}*" } }
        blocks
      end
    end
  end
end
