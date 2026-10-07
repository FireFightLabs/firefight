module Slack
  module Messages
    module LeadAssignment
      def self.announcement(lead_platform_user_id:, lead_name: nil)
        [
          {
            type: "section",
            text: { type: "mrkdwn", text: ":firefighter: #{Mrkdwn.person(lead_platform_user_id, lead_name)} is now the *Incident Lead*" }
          },
          {
            type: "context",
            elements: [ { type: "mrkdwn", text: "Responsible for coordinating the response and updates" } ]
          }
        ]
      end
    end
  end
end
