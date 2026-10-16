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

      def self.invite_failed(lead_platform_user_id:, lead_name: nil)
        "Couldn't add #{Mrkdwn.person(lead_platform_user_id, lead_name)} to this channel, so they may not see updates here. " \
          "They can join the channel themselves, or you can invite them with `/ff invite`."
      end
    end
  end
end
