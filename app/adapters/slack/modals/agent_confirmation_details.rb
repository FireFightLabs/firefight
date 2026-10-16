module Slack
  module Modals
    # Everything a request to approve a change keeps off its card: where it runs, Halon's own sentence and how to put it
    # back, what it touches, the reads Halon named as its reasons, what was read from outside before it asked, and the
    # call as the tool is given it. Everything here came from the model or other systems, so it is escaped.
    module AgentConfirmationDetails
      TITLE = "Details".freeze
      TOOL = "tool".freeze
      WHERE = "Where".freeze
      WHAT = "What Halon said".freeze
      TOUCHES = "What it touches".freeze
      CALL = "The call".freeze
      WARNING = :warning
      # A browser send is asked about under the screenshot of the page it sends from, posted just before.
      PAGE_ABOVE = "The page this sends from is in the screenshot posted above the request, as Halon's browser saw it before stopping.".freeze

      # rich is whether the workspace's Slack shows the newer blocks, so the warning about outside text is an alert block.
      def self.build(confirmation, rich: false)
        { type: "modal", title: { type: "plain_text", text: TITLE }, close: { type: "plain_text", text: "Close" }, blocks: blocks(confirmation, rich: rich) }
      end

      def self.blocks(confirmation, rich:)
        sections = [
          "*#{Mrkdwn.escape(confirmation.title)}*",
          (labelled(WHERE, Mrkdwn.escape(confirmation.label)) if confirmation.label),
          (labelled(WHAT, Mrkdwn.escape(confirmation.summary)) if confirmation.summary),
          (labelled(TOUCHES, rows(confirmation.safeguards)) if confirmation.safeguards.any?),
          (PAGE_ABOVE if confirmation.page),
          support(confirmation),
          (WARNING if confirmation.read_lead),
          labelled(CALL, rows([ ([ TOOL, confirmation.tool_name ] if confirmation.tool_name), *confirmation.asked ].compact, moments: true)),
          reads(confirmation)
        ].compact
        sections.flat_map do |text|
          next Blocks::Alert.new(level: Blocks::Alert::LEVEL_WARNING, text: Mrkdwn.escape(confirmation.read_lead)).to_blocks(rich: rich, modal: true) if text == WARNING

          [ { type: "section", text: { type: "mrkdwn", text: text.truncate(Messages::Formatting::SECTION_TEXT_LIMIT) } } ]
        end
      end

      def self.labelled(label, text) = "*#{label}*\n#{text}"

      def self.rows(pairs, moments: false)
        pairs.map do |name, value|
          shown = Mrkdwn.escape(value.to_s)
          "#{Mrkdwn.escape(name.to_s)}: #{moments ? Messages::Formatting.local_moments(shown) : shown}"
        end.join("\n").presence || "-"
      end

      # The reads Halon named as showing the change will help, so the person approves the reasoning too.
      def self.support(confirmation)
        return unless confirmation.support_lead

        points = confirmation.support_points.map do |point|
          [ "• #{Mrkdwn.escape(point.text)}", (" _(#{Mrkdwn.escape(point.source)})_" if point.source) ].join
        end
        labelled(confirmation.support_lead, points.join("\n"))
      end

      def self.reads(confirmation)
        return unless confirmation.read_heading

        listed = confirmation.read_rows.map { |label, said| "• #{Mrkdwn.escape(label)}: #{Mrkdwn.escape(said)}" }
        [ confirmation.read_heading, *listed ].join("\n")
      end
    end
  end
end
