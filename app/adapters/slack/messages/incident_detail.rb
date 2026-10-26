module Slack
  module Messages
    # What the announcement and the pinned message say about an incident, kept in one place so they never drift: a header,
    # the summary in italics, a divider, then a row per field, each led by its own emoji.
    module IncidentDetail
      TEST_NOTE = "#{Slack::Emoji::TEST} Test incident. Not counted in your metrics.".freeze
      # Between the parts of a title, which read as one phrase.
      SEPARATOR = " · ".freeze
      HEADER_LIMIT = 150

      def self.blocks(title:, summary:, severity_name:, status_name:, reporter_id:, reporter_name: nil,
                      lead_id: nil, lead_name: nil, channel_id: nil, relationship_text: nil, custom_fields_text: nil, test: false)
        blocks = [ { type: "header", text: { type: "plain_text", text: "#{Slack::Emoji::DECLARED} #{title}".truncate(HEADER_LIMIT), emoji: true } } ]
        blocks << Slack::Blocks.context(TEST_NOTE) if test
        blocks.concat(summary_blocks(summary))
        blocks << { type: "divider" }
        blocks << Slack::Blocks.section("#{Slack::Emoji::SEVERITY} *Severity:* #{Mrkdwn.escape(severity_name)}")
        blocks << Slack::Blocks.section("#{Slack::Emoji::STATUS} *Status:* #{Mrkdwn.escape(status_name)}")
        blocks << Slack::Blocks.section("#{Slack::Emoji::LEAD} *Lead:* #{Mrkdwn.person(lead_id, lead_name)}") if lead_id.present? || lead_name.present?
        blocks << Slack::Blocks.section("#{Slack::Emoji::DECLARED_BY} *Declared by:* #{Mrkdwn.person(reporter_id, reporter_name)}")
        blocks << Slack::Blocks.section("#{Slack::Emoji::CHANNEL} *Channel:* <##{channel_id}>") if channel_id.present?
        blocks << Slack::Blocks.section(custom_fields_text) if custom_fields_text
        blocks << Slack::Blocks.section(relationship_text) if relationship_text
        blocks
      end

      # Used for the fallback text too, so notifications match the header.
      def self.title_for(incident)
        "#{incident.identifier}#{SEPARATOR}#{incident.name || 'Untitled incident'}"
      end

      def self.for_incident(incident, channel_id: nil)
        blocks(
          title: title_for(incident),
          summary: incident.summary,
          severity_name: incident.incident_severity.name,
          status_name: incident.incident_status.name,
          reporter_id: incident.declared_by&.platform_user_id,
          reporter_name: incident.declared_by&.actor_display_name,
          lead_id: incident.lead&.platform_user_id,
          lead_name: incident.lead&.actor_display_name,
          channel_id: channel_id,
          relationship_text: Formatting.relationship_summary(incident),
          custom_fields_text: Formatting.custom_fields_summary(incident),
          test: incident.is_test?
        )
      end

      # mrkdwn italics end at a line break, so each line is set in italics on its own, and a long summary runs on into
      # further sections rather than passing Slack's limit.
      def self.summary_blocks(summary)
        return [] if summary.blank?

        lines = Formatting.markdown_to_mrkdwn(summary.gsub(/\r\n?/, "\n")).split("\n").map do |line|
          words = line.sub(Formatting::LIST_MARKER, "\\1• ").strip
          words.empty? ? "" : "_#{words}_"
        end
        Formatting.sections(lines.join("\n")).map { |text| Slack::Blocks.section(text) }
      end
      private_class_method :summary_blocks

      def self.join_channel_button(incident, label: "Join channel")
        {
          type: "button",
          text: { type: "plain_text", text: label, emoji: true },
          url: "https://slack.com/app_redirect?team=#{incident.workspace.platform_id}&channel=#{incident.channel_id}",
          action_id: Identifiers::OPEN_INCIDENT_CHANNEL
        }
      end

      # The preview has no incident, so its buttons are inert.
      def self.homepage_button(homepage_url)
        button = {
          type: "button",
          text: { type: "plain_text", text: "Open in Firefight", emoji: true },
          action_id: homepage_url ? Identifiers::INCIDENT_HOMEPAGE : Identifiers::PREVIEW_HOMEPAGE_DISABLED
        }
        button[:url] = homepage_url if homepage_url
        button
      end

      def self.subscribe_button(incident_id)
        button = {
          type: "button",
          text: { type: "plain_text", text: "#{Slack::Emoji::SUBSCRIBE} Subscribe", emoji: true },
          action_id: incident_id ? Identifiers::SUBSCRIBE_INCIDENT : Identifiers::PREVIEW_SUBSCRIBE_DISABLED
        }
        button[:value] = incident_id if incident_id
        button
      end
    end
  end
end
