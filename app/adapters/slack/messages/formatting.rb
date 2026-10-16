module Slack
  module Messages
    module Formatting
      # The most text Slack takes in one section block.
      SECTION_TEXT_LIMIT = 3000
      LIST_MARKER = /\A([ \t]*)[-*+][ \t]+/
      CODE_FENCE = /\A[ \t]*```/
      # Between the parts of a state or footer line. Never a pipe.
      SEPARATOR = "  ·  ".freeze
      # A message holds at most 50 blocks. A long reply runs on into further messages below this many, leaving room for
      # what follows it, such as the sources line.
      MESSAGE_BLOCK_LIMIT = 45
      # Room to close a code block a section ends inside and open it again in the next.
      FENCE = "```".freeze
      FENCE_ROOM = FENCE.length + 1
      # A markdown link, its address allowed one level of parentheses and an optional title, as models write them.
      MARKDOWN_LINK = /\[([^\]\n]+)\]\((https?:\/\/(?:[^()\s]|\([^()\s]*\))+)(?:\s+"[^"\n]*")?\)/

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

      # Single-asterisk italic is left alone because it collides with mrkdwn
      # bold. The model is asked to use underscores instead.
      def self.markdown_to_mrkdwn(text)
        return "" if text.nil?

        out = text.dup
        out.gsub!(MARKDOWN_LINK) { "<#{Regexp.last_match(2).delete('<>|')}|#{Regexp.last_match(1).delete('<>|')}>" }
        out.gsub!(/^\#{1,6}\s+(.+)$/, "*\\1*")
        out.gsub!(/\*\*(.+?)\*\*/m, "*\\1*")
        out.gsub!(/__(.+?)__/m, "*\\1*")
        out
      end

      # Text as sections that each fit Slack's limit, broken at line ends, then at spaces, and only mid word for a word
      # longer than a section. Nothing is dropped. A code block a break falls inside is closed and opened again, so both
      # halves still read as code. Links hold no spaces, so a break never splits one.
      def self.sections(text, limit: SECTION_TEXT_LIMIT)
        width = limit - FENCE_ROOM * 2
        lines = text.to_s.gsub(/\r\n?/, "\n").split("\n", -1).flat_map { |line| line.length > width ? wrapped(line, width) : [ line ] }
        in_code = false
        built = lines.each_with_object([ +"" ]) do |line, chunks|
          if chunks.last.present? && chunks.last != FENCE && chunks.last.length + 1 + line.length > width
            chunks.last << "\n#{FENCE}" if in_code
            chunks << (in_code ? +FENCE : +"")
          end
          chunks.last << "\n" unless chunks.last.empty?
          chunks.last << line
          in_code = !in_code if line.match?(CODE_FENCE)
        end
        built.map(&:strip).reject { |chunk| chunk.empty? || chunk == FENCE }
      end

      def self.wrapped(line, width)
        rest = line
        pieces = []
        while rest.length > width
          cut = rest.rindex(/\s/, width)
          cut = width if cut.nil? || cut.zero?
          pieces << rest[0, cut].rstrip
          rest = rest[cut..].lstrip
        end
        pieces << rest
      end
      private_class_method :wrapped

      # Blocks as one or more messages, each under Slack's block limit, in order.
      def self.message_parts(blocks)
        blocks.each_slice(MESSAGE_BLOCK_LIMIT).to_a.presence || [ [] ]
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
