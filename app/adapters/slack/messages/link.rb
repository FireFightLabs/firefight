module Slack
  module Messages
    module Link
      def self.related(_source, target, linked_by_platform_user_id:)
        channel_ref = target.channel_id ? "  ·  <##{target.channel_id}>" : ""
        detail = "#{target.incident_severity.name}  ·  #{target.incident_status.name}#{channel_ref}"

        [
          { type: "section", text: { type: "mrkdwn", text: ":link:  *Related incident linked*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "*#{target.identifier}* — #{target.name || 'Untitled Incident'}\n#{detail}" } },
          { type: "context", elements: [ { type: "mrkdwn", text: "Linked by <@#{linked_by_platform_user_id}>" } ] }
        ]
      end

      def self.duplicate_source(_source, canonical, linked_by_platform_user_id:)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":repeat:  *This incident has been marked as a duplicate*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "Merged into *#{canonical.identifier}* — #{canonical.name || 'Untitled Incident'}\n#{canonical.incident_severity.name}  ·  #{canonical.incident_status.name}" } }
        ]
        blocks << { type: "section", text: { type: "mrkdwn", text: ":point_right: Continue in <##{canonical.channel_id}>" } } if canonical.channel_id
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: "Merged by <@#{linked_by_platform_user_id}>" } ] }
        blocks
      end

      def self.duplicate_canonical(source, _canonical, linked_by_platform_user_id:)
        detail = "#{source.incident_severity.name}  ·  #{source.incident_status.name}"
        detail += "  ·  <##{source.channel_id}>" if source.channel_id

        [
          { type: "section", text: { type: "mrkdwn", text: ":repeat:  *Duplicate incident merged in*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "*#{source.identifier}* — #{source.name || 'Untitled Incident'}\n#{detail}" } },
          { type: "context", elements: [ { type: "mrkdwn", text: "Merged by <@#{linked_by_platform_user_id}>" } ] }
        ]
      end
    end
  end
end
