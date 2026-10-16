module Slack
  module Messages
    # A card whose body is never cut. A body that fits Slack's card goes inside it. A longer one, and every body of a card
    # drawn plain, follows as sections (before the buttons when plain), quoted line by line when a person wrote it.
    # card takes what Blocks::Card takes apart from the body.
    module WholeCard
      def self.build(rich:, body: nil, quoted: false, **card)
        inside = rich && body.present? && body.length <= Slack::Blocks::Card::BODY_LIMIT
        blocks = Slack::Blocks::Card.new(**card, body: (body if inside)).to_blocks(rich: rich)
        return blocks if inside || body.blank?

        sections = (quoted ? Formatting.body_sections(body) : Formatting.sections(body)).map { |text| Slack::Blocks.section(text) }
        return blocks + sections if rich

        at = blocks.index { |block| block[:type] == "actions" } || blocks.size
        blocks.insert(at, { type: "divider" }, *sections)
      end
    end
  end
end
