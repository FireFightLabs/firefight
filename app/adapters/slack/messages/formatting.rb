module Slack
  module Messages
    module Formatting
      # The most text Slack takes in one section block.
      SECTION_TEXT_LIMIT = 3000
      LIST_MARKER = /\A([ \t]*)[-*+][ \t]+/
      CODE_FENCE = /\A[ \t]*```/

      # A time of day each reader sees in their own time zone, with UTC for a client that cannot show it.
      def self.slack_time(time) = "<!date^#{time.to_i}^{time}|#{time.utc.strftime('%H:%M UTC')}>"

      # Text with each moment (Chat::TimeToken) as a date and time each reader sees in their own time zone. Escape the
      # text first, since the date is Slack's own markup.
      def self.local_moments(text)
        Chat::TimeToken.replace(text) { |time| "<!date^#{time.to_i}^{date_long_pretty} at {time}|#{time.utc.strftime('%a %-d %b %Y, %H:%M UTC')}>" }
      end

      def self.format_duration(minutes)
        return "N/A" if minutes.nil?

        if minutes < 60
          "#{minutes}m"
        elsif minutes < 1440
          hours = minutes / 60
          remaining_minutes = minutes % 60
          remaining_minutes > 0 ? "#{hours}h #{remaining_minutes}m" : "#{hours}h"
        else
          days = minutes / 1440
          remaining_hours = (minutes % 1440) / 60
          remaining_hours > 0 ? "#{days}d #{remaining_hours}h" : "#{days}d"
        end
      end

      def self.type_diff_text(previous_name, current_name)
        return nil if previous_name.nil? && current_name.nil?

        if previous_name.nil?
          "Type: *#{current_name}*"
        elsif current_name.nil?
          "Type: ~#{previous_name}~ → _none_"
        elsif previous_name != current_name
          "Type: ~#{previous_name}~ → *#{current_name}*"
        else
          "Type: *#{current_name}*"
        end
      end

      def self.diff_text(label, previous_name, current_name)
        if previous_name.present? && previous_name != current_name
          "#{label}: ~#{previous_name}~ → *#{current_name}*"
        else
          "#{label}: *#{current_name}*"
        end
      end

      def self.relationship_summary(incident)
        parts = []

        related = incident.related_incidents.to_a
        if related.any?
          links = related.map { |i| "#{i.identifier}#{i.channel_id ? " (<##{i.channel_id}>)" : ""}" }
          parts << ":link:  *Related:* #{links.join(', ')}"
        end

        dupes = incident.duplicates
        if dupes.any?
          links = dupes.map { |i| "#{i.identifier}#{i.channel_id ? " (<##{i.channel_id}>)" : ""}" }
          parts << ":repeat:  *Duplicates:* #{links.join(', ')}"
        end

        canonical = incident.duplicate_of
        if canonical
          parts << ":repeat:  *Duplicate of:* #{canonical.identifier}#{canonical.channel_id ? " (<##{canonical.channel_id}>)" : ""}"
        end

        parts.any? ? parts.join("\n\n") : nil
      end

      def self.custom_fields_summary(incident)
        fields = incident.custom_fields_for_display
        return nil if fields.blank?

        definitions = incident.workspace.incident_field_definitions.active.index_by(&:slug)

        lines = fields.filter_map do |key, value|
          next if value.blank?

          label = definitions[key]&.name || key.humanize
          formatted = value.is_a?(Array) ? value.join(", ") : value.to_s
          ":label: *#{label}:* #{formatted}"
        end

        lines.any? ? lines.join("\n") : nil
      end

      def self.severity_emoji(_severity)
        ":fire:"
      end

      # A markdown link, whose address may hold one level of parentheses, as a page's name often does, and may carry a title.
      MARKDOWN_LINK = %r{\[(?<label>(?:[^\[\]\n]|\[[^\[\]\n]*\])+)\]\(\s*<?(?<url>https?://(?:[^()\s<>]|\([^()\s<>]*\))+)>?(?:\s+"[^"\n]*")?\s*\)}
      # Slack's own link, as the model may write it. One already escaped by Mrkdwn.escape stays escaped, since that is how
      # outside text is kept from faking a link.
      SLACK_LINK = %r{<(?<url>https?://[^\s|<>]+)(?:\|(?<label>[^<>\n]*))?>}
      # Never ending on punctuation or a bold marker that closes the sentence around it.
      BARE_URL = %r{https?://[^\s<>|]*[^\s<>|*_.,;:!?)\]]}
      LINKS = Regexp.union(MARKDOWN_LINK, SLACK_LINK, BARE_URL)
      WRITTEN_LINKS = [ MARKDOWN_LINK, SLACK_LINK ].freeze
      # Stands in for a link while the rest is converted, so nothing in an address is ever read as bold.
      HELD_LINK = "\u0000%d\u0000".freeze
      HELD_LINK_PATTERN = /\u0000(\d+)\u0000/

      # Single-asterisk italic is left alone because it collides with mrkdwn
      # bold. The model is asked to use underscores instead.
      # Every link becomes Slack's own, whichever form it was written in, and is set aside while the rest is converted.
      def self.markdown_to_mrkdwn(text)
        return "" if text.nil?

        links = []
        out = text.gsub(LINKS) do
          links << slack_link(Regexp.last_match.to_s)
          format(HELD_LINK, links.size - 1)
        end
        out.gsub!(/^\#{1,6}\s+(.+)$/, "*\\1*")
        out.gsub!(/\*\*(.+?)\*\*/m, "*\\1*")
        out.gsub!(/__(.+?)__/m, "*\\1*")
        out.gsub(HELD_LINK_PATTERN) { links[Regexp.last_match(1).to_i] }
      end

      # The agent's words escaped like any outside text, except the links it wrote, which become Slack's own so they can
      # be followed.
      def self.escaped_with_links(text)
        text = text.to_s
        shown = +""
        last = 0
        text.to_enum(:scan, LINKS).each do
          match = Regexp.last_match
          shown << Mrkdwn.escape(text[last...match.begin(0)]) << slack_link(match.to_s, escaped: true)
          last = match.end(0)
        end
        shown << Mrkdwn.escape(text[last..])
      end

      # A label never carries | or an unescaped angle bracket, either of which ends a Slack link early. escaped is for words
      # escaped around the link, so its address and label are escaped too. A bare address stays as it was.
      def self.slack_link(found, escaped: false)
        written = WRITTEN_LINKS.lazy.map { |pattern| pattern.match(found) }.find { |match| match && match[0] == found }
        return escaped ? Mrkdwn.escape(found) : found unless written

        url = escaped ? Mrkdwn.escape(written[:url]) : written[:url]
        label = written[:label].to_s.tr("|", "/")
        label = escaped ? Mrkdwn.escape(label) : label.gsub("<", "&lt;").gsub(">", "&gt;")
        label.strip.empty? ? "<#{url}>" : "<#{url}|#{label.strip}>"
      end

      # Text Slack reads as markdown, such as a streamed answer, does not read Slack's own <url|label>, so it is written
      # as a markdown link. A bare <url> is a link in both.
      def self.mrkdwn_links_to_markdown(text)
        text.to_s.gsub(SLACK_LINK) do
          match = Regexp.last_match
          next match.to_s if match[:label].blank?

          label = match[:label].gsub(/[\[\]]/) { |bracket| "\\#{bracket}" }
          "[#{label}](#{match[:url].gsub('(', '%28').gsub(')', '%29')})"
        end
      end

      # What a person typed, as a message's body, quoted line by line and split before Slack's section limit.
      def self.quoted_blocks(text)
        return [] if text.blank?

        body_sections(text).map { |section| { type: "section", text: { type: "mrkdwn", text: section } } }
      end

      # Quoting adds two characters a line, so a long body runs on into another section rather than failing the post.
      def self.body_sections(message)
        sections = quoted_markdown(message).each_line.each_with_object([ +"" ]) do |line, built|
          built << +"" if built.last.present? && built.last.length + line.length > SECTION_TEXT_LIMIT
          built.last << line
        end
        sections.map { |section| section.chomp.truncate(SECTION_TEXT_LIMIT) }
      end

      # mrkdwn quotes one line per > and draws no list from a markdown marker.
      def self.quoted_markdown(text)
        in_code = false
        markdown_to_mrkdwn(text.to_s.gsub(/\r\n?/, "\n")).split("\n", -1).map do |line|
          in_code = !in_code if line.match?(CODE_FENCE)
          line = line.sub(LIST_MARKER, "\\1• ") unless in_code
          line.strip.empty? ? ">" : "> #{line}"
        end.join("\n")
      end
    end
  end
end
