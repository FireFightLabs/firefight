module Slack
  module Messages
    # An incident's resolution, as an alert saying who resolved it and how long it took, then the summary. In the channel
    # it also offers the postmortem.
    module Resolution
      def self.build(incident, resolved_by_platform_user_id:, rich:, resolved_by_name: nil)
        blocks = common(incident, resolved_by_platform_user_id, resolved_by_name, rich)
        blocks.concat(postmortem_offer(incident)) if incident.postmortem_blocked_reason.nil?
        blocks
      end

      def self.announcement_thread(incident, resolved_by_platform_user_id:, rich:, resolved_by_name: nil)
        common(incident, resolved_by_platform_user_id, resolved_by_name, rich)
      end

      # "Resolved by @Dana after 1h 12m", the line the alert and a subscriber's direct message share.
      def self.headline(incident, resolved_by_platform_user_id, resolved_by_name = nil)
        line = "Resolved by #{Mrkdwn.person(resolved_by_platform_user_id, resolved_by_name)}"
        incident.time_to_resolve.nil? ? line : "#{line} after #{Formatting.format_duration(incident.time_to_resolve)}"
      end

      def self.common(incident, resolved_by_platform_user_id, resolved_by_name, rich)
        alert = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::LEVEL_SUCCESS, text: headline(incident, resolved_by_platform_user_id, resolved_by_name),
                                         emoji: Slack::Emoji::RESOLVED)
        [
          *alert.to_blocks(rich: rich),
          { type: "divider" },
          *summary_blocks(incident),
          Slack::Blocks.context("#{Slack::Emoji::SEVERITY} #{incident.incident_severity.name}")
        ]
      end
      private_class_method :common

      def self.postmortem_offer(incident)
        [
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: "Write the postmortem", emoji: true },
                action_id: Identifiers::WRITE_POSTMORTEM,
                value: incident.id,
                style: "primary"
              }
            ]
          },
          { type: "context", elements: [ { type: "mrkdwn", text: sources_text(incident) } ] }
        ]
      end

      def self.summary_blocks(incident)
        return [ { type: "section", text: { type: "mrkdwn", text: "_No summary provided_" } } ] if incident.summary.blank?

        Formatting.quoted_blocks(incident.summary)
      end

      def self.sources_text(incident)
        count = incident.incident_transcript_messages.kept.count
        if count.zero?
          "Drafted from the timeline only. Sections it cannot fill are left empty for you to write."
        else
          "Drafted from the timeline and the #{count} #{'message'.pluralize(count)} in this channel. You edit it in the dashboard."
        end
      end
    end
  end
end
