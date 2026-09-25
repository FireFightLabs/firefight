module Slack
  module Messages
    # The text that goes with a chart in a thread: its title, the numbers per series, and a link to the live chart. It is
    # the upload's comment, or the whole message when the workspace has not granted file uploads.
    module ChartCaption
      LINK_TEXT = "Open the live chart".freeze

      def self.build(chart)
        lines = [ "*#{Slack::Mrkdwn.escape(chart.title)}*" ]
        lines << Slack::Mrkdwn.escape(chart.summary) if chart.summary.present?
        lines << "<#{chart.link}|#{LINK_TEXT}>" if chart.link.present?
        lines.join("\n")
      end

      def self.filename(chart) = "#{chart.title.parameterize.presence || 'chart'}.png"
    end
  end
end
