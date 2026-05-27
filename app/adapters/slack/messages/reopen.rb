module Slack
  module Messages
    module Reopen
      def self.build(incident, reopened_by_platform_user_id:, reason: nil)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":rotating_light:  *Incident Reopened*" } },
          { type: "divider" }
        ]
        blocks << { type: "section", text: { type: "mrkdwn", text: "> #{reason}" } } if reason.present?
        blocks << {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "Reopened by <@#{reopened_by_platform_user_id}>  |  Status: #{incident.incident_status.name}" }
          ]
        }
        blocks
      end

      def self.announcement_thread(incident, reopened_by_platform_user_id:, reason: nil)
        blocks = [
          { type: "header", text: { type: "plain_text", text: "Incident Reopened", emoji: true } },
          { type: "divider" }
        ]
        blocks << { type: "section", text: { type: "mrkdwn", text: reason } } if reason.present?
        blocks << { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: Reopened by: *<@#{reopened_by_platform_user_id}>*" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":bar_chart: Status: *#{incident.incident_status.name}*" } }
        blocks
      end
    end
  end
end
