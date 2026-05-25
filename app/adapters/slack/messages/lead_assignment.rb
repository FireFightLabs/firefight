module Slack
  module Messages
    module LeadAssignment
      def self.announcement(lead_platform_user_id:)
        [
          {
            type: "section",
            text: { type: "mrkdwn", text: ":firefighter: <@#{lead_platform_user_id}> is now the *Incident Lead*" }
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
