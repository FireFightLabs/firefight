module Slack
  # A message as someone wrote it in Slack, as plain text for a place that shows text as typed, such as a form field or
  # the dashboard's chat. Mentions, emoji and escaped characters read as Slack shows them, and formatting marks drop away
  # rather than showing literally.
  module MessageText
    # Bold, italics and strikes, each one mark either side of words, as Slack reads them.
    STYLE = /(?<![\w\\])([*_~])(?=\S)([^\n]+?)(?<=\S)\1(?!\w)/
    # The address a link Slack made from something typed carries, beside the words it was made from.
    SCHEME = %r{\A(?:https?://|mailto:)}

    # names maps a platform user id to the name to show for it.
    def self.convert(text, names: {})
      text.to_s.split(MessageMarkdown::FENCE, -1).each_with_index.map do |part, index|
        index.odd? ? code(part.delete_prefix("\n").delete_suffix("\n"), names) : prose(part, names)
      end.join.strip
    end

    def self.prose(text, names)
      text.split(MessageMarkdown::INLINE_CODE, -1).each_with_index.map do |part, index|
        index.odd? ? code(part, names) : styled(part, names)
      end.join
    end

    # Links and mentions are set aside first, so dropping marks never reaches inside an address or a name.
    def self.styled(text, names)
      tokens = []
      marked = text.gsub(MessageMarkdown::TOKEN) do
        tokens << token(Regexp.last_match(1), names)
        "\u0000#{tokens.size - 1}\u0000"
      end
      unstyled = marked
      unstyled = unstyled.gsub(STYLE, "\\2") while unstyled.match?(STYLE)
      shortcodes(MessageMarkdown.decode(unstyled)).gsub(MessageMarkdown::PLACEHOLDER) { tokens[Regexp.last_match(1).to_i] }
    end

    def self.code(text, names)
      MessageMarkdown.decode(text.gsub(MessageMarkdown::TOKEN) { MessageMarkdown.token_text(Regexp.last_match(1), names) })
    end

    def self.token(token, names)
      target, label = token.split("|", 2)
      return MessageMarkdown.decode(MessageMarkdown.token_text(token, names)) if target.start_with?("@", "#", "!")

      address = MessageMarkdown.decode(target)
      words = shortcodes(MessageMarkdown.decode(label.to_s))
      return address if words.blank?
      return words if address.sub(SCHEME, "").chomp("/") == words.chomp("/")

      "#{words} (#{address})"
    end

    def self.shortcodes(text)
      text.gsub(MessageMarkdown::SHORTCODE) { |code| MessageMarkdown.emoji(code) || code }
    end

    private_class_method :prose, :styled, :code, :token, :shortcodes
  end
end
