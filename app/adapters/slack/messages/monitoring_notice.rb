module Slack
  module Messages
    # A slow problem Halon found on its own from a scheduled check: what it is about, what is happening and by when, how
    # soon someone needs to act, and the run that showed it. Said once, and again only when it got worse, which the
    # footer says so nobody waits for a reminder.
    module MonitoringNotice
      TITLES = {
        Investigation::Notice::SIGNAL_DISK => ":floppy_disk:", Investigation::Notice::SIGNAL_CERTIFICATE => ":lock:",
        Investigation::Notice::SIGNAL_ERROR_BUDGET => ":chart_with_downwards_trend:", Investigation::Notice::SIGNAL_COST => ":money_with_wings:",
        Investigation::Notice::SIGNAL_LEAKED_SECRET => ":key:", Investigation::Notice::SIGNAL_OTHER => ":mag:"
      }.freeze

      def self.build(notice)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{TITLES.fetch(notice.signal, ':mag:')}  *#{Mrkdwn.escape(title(notice))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(notice.summary).truncate(Formatting::SECTION_TEXT_LIMIT) } },
          { type: "section", text: { type: "mrkdwn", text: fields(notice).join("  ·  ") } },
          { type: "context", elements: [ { type: "mrkdwn", text: footer(notice) } ] }
        ]
        url = notice.investigation && DashboardUrl.investigation(notice.investigation)
        blocks << { type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: "Open the run" }, url: url } ] } if url
        blocks
      end

      def self.title(notice) = "#{Investigation::Notice::SIGNAL_LABELS.fetch(notice.signal)}: #{notice.topic}".truncate(150)

      def self.fallback(notice) = "#{title(notice)}. #{notice.summary}".truncate(300)

      def self.fields(notice)
        [
          "*Urgency:* #{Investigation::Notice::SEVERITY_LABELS.fetch(notice.severity)}",
          ("*Becomes a problem:* #{notice.due_words}" if notice.due_on),
          ("*Resource:* #{Mrkdwn.escape(notice.resource.name)}" if notice.resource)
        ].compact
      end

      def self.footer(notice)
        from = notice.check ? "Halon's #{Mrkdwn.escape(notice.check.name)} check" : "Halon"
        again = notice.times_said.positive? ? "Halon said this before, and it got worse or came back." : "Halon says it again only if it gets worse."
        "#{from}  ·  #{again}"
      end
    end
  end
end
