require "test_helper"

class Slack::Blocks::CardTest < ActiveSupport::TestCase
  BUTTON = { type: "button", text: { type: "plain_text", text: "Done" }, action_id: "done", value: "1" }.freeze

  test "a card is Slack's card block where the workspace shows it, its words cut to Slack's limits" do
    card = Slack::Blocks::Card.new(title: "Fix for INC-003", subtitle: "Applied by Uros", body: "x" * 300, actions: [ BUTTON ], icon: ":x:")

    block = card.to_blocks(rich: true).sole

    assert_equal [ "card", ":x:  Fix for INC-003", "Applied by Uros", 200, [ BUTTON ] ],
                 [ block[:type], block.dig(:title, :text), block.dig(:subtitle, :text), block.dig(:body, :text).size, block[:actions] ]
    assert_not block.key?(:hero_image)
  end

  test "a workspace without card blocks gets the same words as a section, a context line and the buttons" do
    blocks = Slack::Blocks::Card.new(title: "Fix for INC-003", subtitle: "Applied by Uros", body: "Two steps.", actions: [ BUTTON ]).to_blocks(rich: false)

    assert_equal [ "*Fix for INC-003*\nTwo steps.", "Applied by Uros", [ BUTTON ] ],
                 [ blocks.first.dig(:text, :text), blocks.second.dig(:elements, 0, :text), blocks.third[:elements] ]
  end

  test "a card leaves out what it was not given, and holds three buttons at most" do
    assert_equal [ { type: "card", body: { type: "mrkdwn", text: "Your step." } } ], Slack::Blocks::Card.new(title: nil, body: "Your step.").to_blocks(rich: true)
    assert_raises(ArgumentError) { Slack::Blocks::Card.new(title: "Too many", actions: [ BUTTON ] * 4) }
  end
end
