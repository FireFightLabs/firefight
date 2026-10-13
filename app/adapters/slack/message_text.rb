module Slack
  # A message as someone wrote it in Slack, as plain text for a place that shows text as typed, such as a form field or
  # the dashboard's chat. Mentions, emoji and escaped characters read as Slack shows them, and formatting marks drop away
  # rather than showing literally.
  #
  # for_model is the reading a model is given instead. A person or a channel keeps its id beside its name, so the model
  # can hand it to a tool, and code keeps its backticks, which a model reads as code.
  module MessageText
    # Bold, italics and strikes, each one mark either side of words, as Slack reads them.
    STYLE = /(?<![\w\\])([*_~])(?=\S)([^\n]+?)(?<=\S)\1(?!\w)/
    # The address a link Slack made from something typed carries, beside the words it was made from.
    SCHEME = %r{\A(?:https?://|mailto:)}
    # A fence opens on a line of its own, and the line before it is not doubled.
    FENCE_SPACING = /\n+(```\n)/

    # names maps a platform user id to the name to show for it.
    def self.convert(text, names: {}, for_model: false)
      read = text.to_s.split(MessageMarkdown::FENCE, -1).each_with_index.map do |part, index|
        next prose(part, names, for_model) if index.even?

        code = code(part.delete_prefix("\n").delete_suffix("\n"), names)
        for_model ? "\n```\n#{code}\n```\n" : code
      end.join
      (for_model ? read.gsub(FENCE_SPACING, "\n\\1") : read).strip
    end

    def self.prose(text, names, for_model)
      text.split(MessageMarkdown::INLINE_CODE, -1).each_with_index.map do |part, index|
        next styled(part, names, for_model) if index.even?

        for_model ? "`#{code(part, names)}`" : code(part, names)
      end.join
    end

    # Links and mentions are set aside first, so dropping marks never reaches inside an address or a name.
    def self.styled(text, names, for_model)
      tokens = []
      marked = text.gsub(MessageMarkdown::TOKEN) do
        tokens << token(Regexp.last_match(1), names, for_model)
        "\u0000#{tokens.size - 1}\u0000"
      end
      unstyled = marked
      unstyled = unstyled.gsub(STYLE, "\\2") while unstyled.match?(STYLE)
      shortcodes(MessageMarkdown.decode(unstyled)).gsub(MessageMarkdown::PLACEHOLDER) { tokens[Regexp.last_match(1).to_i] }
    end

    def self.code(text, names)
      MessageMarkdown.decode(text.gsub(MessageMarkdown::TOKEN) { MessageMarkdown.token_text(Regexp.last_match(1), names) })
    end

    def self.token(token, names, for_model)
      target, label = token.split("|", 2)
      return with_id(target, label, names) if for_model && target.start_with?("@", "#", "!subteam^")
      return MessageMarkdown.decode(MessageMarkdown.token_text(token, names)) if target.start_with?("@", "#", "!")

      address = MessageMarkdown.decode(target)
      words = shortcodes(MessageMarkdown.decode(label.to_s))
      return address if words.blank?
      return words if address.sub(SCHEME, "").chomp("/") == words.chomp("/")

      "#{words} (#{address})"
    end

    # A person, a channel or a group by its name with its id after it, or by its id alone when no name is known.
    def self.with_id(target, label, names)
      id = target.delete_prefix("!subteam^").delete_prefix("@").delete_prefix("#")
      mark = target.start_with?("#") ? "#" : "@"
      name = names[id].presence || MessageMarkdown.decode(label.to_s).delete_prefix(mark).presence
      name ? "#{mark}#{name} (#{id})" : "#{mark}#{id}"
    end

    def self.shortcodes(text)
      text.gsub(MessageMarkdown::SHORTCODE) { |code| MessageMarkdown.emoji(code) || code }
    end

    private_class_method :prose, :styled, :code, :token, :with_id, :shortcodes
  end
end
