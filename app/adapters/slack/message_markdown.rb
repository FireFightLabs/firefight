module Slack
  # A message as someone wrote it in Slack, as the markdown the dashboard renders. Slack escapes &, < and >, wraps
  # links, mentions and channels in angle brackets, and writes bold with one asterisk, which markdown reads as italic.
  module MessageMarkdown
    FENCE = /```(.*?)```/m
    INLINE_CODE = /`([^`\n]+)`/
    TOKEN = /<([^<>\n]+)>/
    MENTION = /<@([A-Z0-9]+)(?:\|[^<>]*)?>/
    BOLD = /(?<![\w*\\])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])/
    QUOTE_LINE = /^&gt;[ \t]?/
    # Slack quotes one line per marker, where markdown would carry the quote on into the next line.
    QUOTE_END = /^(>.*)\n(?!>)/
    # Characters Slack shows as typed that markdown would read as a link or a heading.
    LITERAL = /[\\\[\]]/
    HEADING = /^([ \t]*)#/
    ENTITIES = { "&amp;" => "&", "&lt;" => "<", "&gt;" => ">" }.freeze
    PLACEHOLDER = /\u0000(\d+)\u0000/

    # The platform user ids the text mentions, so their names can be loaded once for many messages.
    def self.mentioned_ids(text)
      text.to_s.scan(MENTION).flatten.uniq
    end

    # names maps a platform user id to the name to show for it.
    def self.convert(text, names: {})
      text.to_s.split(FENCE, -1).each_with_index.map do |part, index|
        index.odd? ? fenced(part, names) : prose(part, names)
      end.join.strip
    end

    def self.fenced(code, names)
      "\n```\n#{plain(code, names).delete_prefix("\n").delete_suffix("\n")}\n```\n"
    end

    def self.prose(text, names)
      text.split(INLINE_CODE, -1).each_with_index.map do |part, index|
        index.odd? ? "`#{plain(part, names)}`" : formatted(part, names)
      end.join
    end

    # Links and mentions are set aside first, so escaping and bold never reach inside a link's address.
    def self.formatted(text, names)
      tokens = []
      marked = text.gsub(TOKEN) do
        tokens << token_markdown(Regexp.last_match(1), names)
        "\u0000#{tokens.size - 1}\u0000"
      end
      marked
        .gsub(QUOTE_LINE, "> ").gsub(QUOTE_END, "\\1\n\n")
        .gsub(LITERAL) { |char| "\\#{char}" }.gsub(HEADING, "\\1\\#")
        .gsub(BOLD, "**\\1**")
        .gsub(PLACEHOLDER) { tokens[Regexp.last_match(1).to_i] }
    end

    # Code shows what was typed, so entities are decoded and a link or mention reads as its text.
    def self.plain(text, names)
      decode(text.gsub(TOKEN) { token_text(Regexp.last_match(1), names) })
    end

    # Text stays entity encoded, as Slack sent it, so markdown decodes it and never reads it as HTML.
    def self.token_markdown(token, names)
      target, label = token.split("|", 2)
      return escape(token_text(token, names)) if target.start_with?("@", "#", "!")

      "[#{escape(label.presence || target)}](<#{decode(target)}>)"
    end

    # Encoded the way Slack encodes text, a name from Firefight included.
    def self.token_text(token, names)
      target, label = token.split("|", 2)
      case target[0]
      when "@" then "@#{person(names[target[1..]], label)}"
      when "#" then "##{label.presence || 'channel'}"
      when "!" then special(target, label)
      else label.presence || target
      end
    end

    # Someone with no seat in the workspace is named by the label Slack sent, if any.
    def self.person(name, label)
      return Slack::Mrkdwn.escape(name) if name.present?

      label.presence || "someone"
    end

    # <!here>, <!channel> and <!everyone> notify a channel, and a group or a date carries its own words as the label.
    def self.special(target, label)
      return label if label.present?

      "@#{target[1..].split('^').first}"
    end

    def self.escape(text)
      text.gsub(/[\\\[\]*_`]/) { |char| "\\#{char}" }
    end

    def self.decode(text)
      text.gsub(Regexp.union(ENTITIES.keys), ENTITIES)
    end

    private_class_method :fenced, :prose, :formatted, :plain, :token_markdown, :token_text, :person, :special, :escape, :decode
  end
end
