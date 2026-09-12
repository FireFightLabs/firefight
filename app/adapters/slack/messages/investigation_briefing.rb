module Slack
  module Messages
    # Renders the investigation's stored seed pack, so the channel reads exactly
    # what the agent was given.
    module InvestigationBriefing
      SECTION_TEXT_LIMIT = 3000
      ALERT_ROWS = 5
      FIELDS_PER_ALERT = 6
      PAST_ROWS = 3

      def self.build(incident:, seed_pack:)
        facts = seed_pack["incident"].to_h

        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":mag:  *What I know about #{Mrkdwn.escape(incident.identifier)}*" } },
          { type: "divider" }
        ]
        summary = summary_line(facts)
        people = people_fields(facts)
        blocks << section(summary) if summary
        blocks << section(state_fields(facts))
        blocks << section(people) if people
        blocks.concat(list_section("Alerts", alert_lines(seed_pack)))
        blocks.concat(list_section("Runbooks attached", runbook_lines(seed_pack)))
        blocks.concat(list_section("Seen before, same alert fingerprint", past_lines(seed_pack)))
        blocks << footer
        blocks
      end

      def self.fallback_text(incident:, seed_pack:)
        counts = [
          "#{seed_pack["alerts"].to_a.size} #{"alert".pluralize(seed_pack["alerts"].to_a.size)}",
          "#{seed_pack["past_incidents"].to_a.size} similar past #{"incident".pluralize(seed_pack["past_incidents"].to_a.size)}"
        ]
        "What I know about #{incident.identifier}: #{counts.join(", ")}."
      end

      def self.section(text)
        { type: "section", text: { type: "mrkdwn", text: text[0, SECTION_TEXT_LIMIT] } }
      end

      def self.summary_line(facts)
        return nil if facts["summary"].blank?

        "> #{Mrkdwn.escape(facts["summary"])}"
      end

      def self.state_fields(facts)
        fields = [ "*Severity:* #{Mrkdwn.escape(facts["severity"])}", "*Status:* #{Mrkdwn.escape(facts["status"])}" ]
        fields << "*Type:* #{Mrkdwn.escape(facts["type"])}" if facts["type"].present?
        fields.join("  ·  ")
      end

      def self.people_fields(facts)
        fields = []
        fields << "*Lead:* #{person(facts["lead"])}" if facts["lead"].present?
        facts["roles"].to_a.each do |role|
          next if role["member"].blank?

          fields << "*#{Mrkdwn.escape(role["role"])}:* #{person(role["member"])}"
        end
        fields.any? ? fields.join("  ·  ") : nil
      end

      def self.person(membership_facts)
        return "*#{Mrkdwn.escape(membership_facts["name"])}*" if membership_facts["platform_user_id"].blank?

        "<@#{membership_facts["platform_user_id"]}>"
      end

      # One section per group rather than one block per row, so a long pack cannot
      # approach Slack's 50 block cap.
      def self.list_section(heading, lines)
        return [] if lines.empty?

        [ section("*#{heading}*\n#{lines.join("\n")}") ]
      end

      def self.alert_lines(seed_pack)
        alerts = seed_pack["alerts"].to_a
        lines = alerts.first(ALERT_ROWS).map { |alert| alert_line(alert) }
        held_back = seed_pack["alerts_held_back"].to_i + [ alerts.size - ALERT_ROWS, 0 ].max
        lines << "_#{held_back} more #{"alert".pluralize(held_back)} not shown_" if held_back.positive?
        lines
      end

      def self.alert_line(alert)
        line = "• #{Mrkdwn.escape(alert["source"])}: #{Mrkdwn.escape(alert["title"])} (#{Mrkdwn.escape(alert["status"])})"
        fields = alert["fields"].to_h.first(FIELDS_PER_ALERT)
        return line if fields.empty?

        rendered = fields.map { |key, value| "#{Mrkdwn.escape(key)}=#{Mrkdwn.escape(value.to_s.truncate(60))}" }
        "#{line}\n    #{rendered.join("  ")}"
      end

      def self.runbook_lines(seed_pack)
        seed_pack["runbooks"].to_a.map { |runbook| "• #{Mrkdwn.escape(runbook["name"])}" }
      end

      def self.past_lines(seed_pack)
        seed_pack["past_incidents"].to_a.first(PAST_ROWS).map do |past|
          line = "• *#{Mrkdwn.escape(past["identifier"])}* #{Mrkdwn.escape(past["name"])}"
          line += ", resolved #{past["resolved_at"]}" if past["resolved_at"].present?
          line += "\n    Finding: #{Mrkdwn.escape(past["finding"])}" if past["finding"].present?
          line
        end
      end

      def self.footer
        { type: "context", elements: [ { type: "mrkdwn", text: "Gathered from Firefight's own records" } ] }
      end
    end
  end
end
