module Slack
  module Messages
    # An incident reopened, as an alert saying who reopened it, then why and the status it is back in.
    module Reopen
      def self.build(incident, reopened_by_platform_user_id:, rich:, reopened_by_name: nil, reason: nil)
        alert = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::LEVEL_WARNING, text: headline(reopened_by_platform_user_id, reopened_by_name),
                                         emoji: Slack::Emoji::REOPENED)
        blocks = alert.to_blocks(rich: rich)
        body = Formatting.quoted_blocks(reason)
        blocks << { type: "divider" } if body.any?
        blocks.concat(body)
        blocks << Slack::Blocks.context("Status: #{incident.incident_status.name}")
      end

      def self.announcement_thread(incident, reopened_by_platform_user_id:, rich:, reopened_by_name: nil, reason: nil)
        build(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reopened_by_name: reopened_by_name, reason: reason, rich: rich)
      end

      def self.headline(reopened_by_platform_user_id, reopened_by_name = nil)
        "Reopened by #{Mrkdwn.person(reopened_by_platform_user_id, reopened_by_name)}"
      end
    end
  end
end
