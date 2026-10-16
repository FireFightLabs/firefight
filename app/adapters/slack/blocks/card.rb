module Slack
  module Blocks
    # One thing to read and act on: a title, a line or two, and at most three buttons. Slack's card block where the
    # workspace shows it, otherwise the same words as a section, a context line and the buttons, so nothing is lost to how
    # it looks. title, subtitle and body are mrkdwn the caller already escaped. icon is an emoji shortcode set before the
    # title.
    class Card
      TITLE_LIMIT = 150
      SUBTITLE_LIMIT = 150
      BODY_LIMIT = 200
      ACTIONS_LIMIT = 3

      attr_reader :title, :subtitle, :body, :actions, :icon

      def initialize(title:, subtitle: nil, body: nil, actions: [], icon: nil)
        @title = title
        @subtitle = subtitle
        @body = body
        @actions = Array(actions).compact
        @icon = icon
        raise ArgumentError, "A card holds at most #{ACTIONS_LIMIT} buttons." if @actions.size > ACTIONS_LIMIT
      end

      def to_blocks(rich:) = rich ? [ card ] : plain

      private

      def headline = [ icon, title.presence ].compact.join("  ").presence

      def card
        {
          type: "card", title: (text(headline, TITLE_LIMIT) if headline), subtitle: (text(subtitle, SUBTITLE_LIMIT) if subtitle.present?),
          body: (text(body, BODY_LIMIT) if body.present?), actions: actions.presence
        }.compact
      end

      def text(words, limit) = { type: "mrkdwn", text: words.to_s.truncate(limit) }

      def plain
        said = [ ("*#{headline}*" if headline), body.presence ].compact.join("\n")
        [
          ({ type: "section", text: { type: "mrkdwn", text: said.truncate(Slack::Messages::Formatting::SECTION_TEXT_LIMIT) } } if said.present?),
          ({ type: "context", elements: [ { type: "mrkdwn", text: subtitle.truncate(Slack::Messages::Formatting::SECTION_TEXT_LIMIT) } ] } if subtitle.present?),
          ({ type: "actions", elements: actions } if actions.any?)
        ].compact
      end
    end
  end
end
