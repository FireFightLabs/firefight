require "test_helper"

class Slack::Blocks::CardTest < ActiveSupport::TestCase
  BUTTON = { type: "button", text: { type: "plain_text", text: "Open" }, action_id: "open" }.freeze

  test "rich, a card is one card block with Slack's own fields" do
    blocks = Slack::Blocks::Card.new(title: "INC-1 · Slow", subtitle: "Minor", body: "It is slow", actions: [ BUTTON ], icon: Slack::Emoji::DECLARED)
                                .to_blocks(rich: true)

    assert_equal [ {
      type: "card", title: { type: "mrkdwn", text: "#{Slack::Emoji::DECLARED} INC-1 · Slow" }, subtitle: { type: "mrkdwn", text: "Minor" },
      body: { type: "mrkdwn", text: "It is slow" }, actions: [ BUTTON ]
    } ], blocks
  end

  test "plain, it is the house anatomy: a bold title, the subtitle as context, a divider, the body and the buttons" do
    blocks = Slack::Blocks::Card.new(title: "INC-1 · Slow", subtitle: "Minor", body: "It is slow", actions: [ BUTTON ], icon: Slack::Emoji::DECLARED)
                                .to_blocks(rich: false)

    assert_equal %w[section context divider section actions], blocks.pluck(:type)
    assert_equal "#{Slack::Emoji::DECLARED}  *INC-1 · Slow*", blocks.first.dig(:text, :text)
  end

  test "a body longer than a card holds is drawn whole in sections under it, never cut" do
    body = "word " * 100
    blocks = Slack::Blocks::Card.new(title: "T", body: body).to_blocks(rich: true)

    assert_nil blocks.first[:body]
    assert_equal body.strip, blocks.drop(1).map { |block| block.dig(:text, :text) }.join(" ")
  end

  test "a quoted body is quoted line by line wherever it is drawn in sections" do
    blocks = Slack::Blocks::Card.new(title: "T", body: "one\ntwo", quoted: true).to_blocks(rich: false)

    assert_equal "> one\n> two", blocks.last.dig(:text, :text)
  end

  test "a title too long for a card draws the whole card plain rather than cutting it" do
    title = "x" * 200

    blocks = Slack::Blocks::Card.new(title: title, actions: [ BUTTON ]).to_blocks(rich: true)

    assert_equal "*#{title}*", blocks.first.dig(:text, :text)
  end

  test "a card holds at most three buttons" do
    assert_raises(ArgumentError) { Slack::Blocks::Card.new(title: "T", actions: [ BUTTON ] * 4) }
  end
end
