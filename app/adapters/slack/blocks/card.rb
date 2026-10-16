module Slack
  module Blocks
    # A title, an optional subtitle and body, and at most three buttons.
    #
    #   card = Slack::Blocks::Card.new(title: "INC-003 · Checkout is slow", subtitle: "Minor · Investigating",
    #                                  actions: [ button ], icon: Slack::Emoji::DECLARED)
    #   card.to_blocks(rich: true)  # one card block
    #   card.to_blocks(rich: false) # bold title, subtitle as a context line, divider and body, then the buttons
    #
    # Text is mrkdwn the caller has already escaped, and icon is a shortcode from Slack::Emoji that opens the title.
    # Nothing is ever cut. A title or subtitle past Slack's limit draws the card plain, and a body past its limit is drawn
    # in sections under the card. quoted marks a body a person wrote, quoted line by line wherever it is drawn in
    # sections, as every message quotes what a person wrote.
    class Card
      TITLE_LIMIT = 150
      SUBTITLE_LIMIT = 150
      BODY_LIMIT = 200
      ACTIONS_LIMIT = 3

      attr_reader :title, :subtitle, :body, :actions, :icon, :quoted

      def initialize(title:, subtitle: nil, body: nil, actions: [], icon: nil, quoted: false)
        raise ArgumentError, "A card holds at most #{ACTIONS_LIMIT} buttons, got #{actions.size}" if actions.size > ACTIONS_LIMIT

        @title = title.to_s
        @subtitle = subtitle.presence
        @body = body.presence
        @actions = actions
        @icon = icon
        @quoted = quoted
      end

      def to_blocks(rich:)
        rich && fits? ? rich_blocks : plain_blocks
      end

      private

      def heading = icon ? "#{icon} #{title}" : title

      def fits? = heading.length <= TITLE_LIMIT && subtitle.to_s.length <= SUBTITLE_LIMIT

      def body_fits? = body.to_s.length <= BODY_LIMIT

      def rich_blocks
        card = { type: "card", title: Blocks.mrkdwn(heading) }
        card[:subtitle] = Blocks.mrkdwn(subtitle) if subtitle
        card[:body] = Blocks.mrkdwn(body) if body && body_fits?
        card[:actions] = actions if actions.any?
        return [ card ] if body.nil? || body_fits?

        [ card, *body_sections ]
      end

      def plain_blocks
        blocks = [ Blocks.section(icon ? "#{icon}  *#{title}*" : "*#{title}*") ]
        blocks << Blocks.context(subtitle) if subtitle
        if body
          blocks << { type: "divider" }
          blocks.concat(body_sections)
        end
        blocks << { type: "actions", elements: actions } if actions.any?
        blocks
      end

      def body_sections
        texts = quoted ? Slack::Messages::Formatting.body_sections(body) : Slack::Messages::Formatting.sections(body)
        texts.map { |text| Blocks.section(text) }
      end
    end
  end
end
