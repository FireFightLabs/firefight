module Slack
  module Messages
    # A pull request Halon reviewed as high risk, posted in the channel of the service that owns its repository: why it
    # is risky, the findings still open, and a button to the pull request. The title, the reason and the findings came
    # from the code host or a model, so each is escaped.
    module HighRiskPullRequest
      # How many open findings the message lists before saying how many more.
      SHOWN_FINDINGS = 3

      # alert is a PullRequestReviewAlertService::Shown.
      def self.build(alert)
        [
          { type: "section", text: { type: "mrkdwn", text: "#{Slack::Emoji::HIGH_RISK_CHANGE}  *#{title(alert)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: body(alert) } },
          (findings_block(alert) if alert.findings.any?),
          { type: "context", elements: [ { type: "mrkdwn", text: footer(alert) } ] },
          ({ type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: "Open pull request" }, url: alert.url,
                                              action_id: Identifiers::OPEN_PULL_REQUEST } ] } if alert.url.present?)
        ].compact
      end

      def self.fallback(alert) = "#{title(alert)}: ##{alert.number} #{alert.title}"

      def self.title(alert) = "High risk pull request in #{Slack::Mrkdwn.escape(alert.repository)}"

      def self.body(alert)
        name = Slack::Mrkdwn.escape("##{alert.number} #{alert.title}".strip)
        heading = alert.url.present? ? "*<#{alert.url}|#{name.delete('|>')}>*" : "*#{name}*"
        reason = alert.risk_reason.to_s.strip
        return heading if reason.empty?

        quoted = Slack::Mrkdwn.escape(reason).lines.map { |line| "> #{line.chomp}" }.join("\n")
        "#{heading}\n#{quoted}".truncate(Formatting::SECTION_TEXT_LIMIT)
      end

      def self.findings_block(alert)
        shown = alert.findings.first(SHOWN_FINDINGS).map do |finding|
          lesson = "  ·  _#{Slack::Mrkdwn.escape(finding.lesson)}_" if finding.lesson
          "• *#{finding.severity}*  #{Slack::Mrkdwn.escape(finding.claim)}#{lesson}"
        end
        more = alert.findings.size - SHOWN_FINDINGS
        shown << "and #{more} more on the pull request" if more.positive?
        { type: "section", text: { type: "mrkdwn", text: shown.join("\n") } }
      end

      def self.footer(alert)
        "Halon reviewed it for #{Slack::Mrkdwn.escape(alert.service)}  ·  Turn this off on #{Slack::Mrkdwn.escape(alert.service)} in the catalog"
      end
    end
  end
end
