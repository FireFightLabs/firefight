require "test_helper"

class Slack::Messages::WholeCardTest < ActiveSupport::TestCase
  BUTTON = { type: "button", text: { type: "plain_text", text: "Open" }, action_id: "open" }.freeze

  test "a body that fits goes inside the card" do
    blocks = Slack::Messages::WholeCard.build(rich: true, title: "T", body: "Short", actions: [ BUTTON ])

    assert_equal "Short", blocks.sole.dig(:body, :text)
  end

  test "a body longer than a card holds follows it whole, never cut" do
    body = "word " * 100
    blocks = Slack::Messages::WholeCard.build(rich: true, title: "T", body: body)

    assert_nil blocks.first[:body]
    assert_equal body.strip, blocks.drop(1).map { |block| block.dig(:text, :text) }.join(" ")
  end

  test "drawn plain, a person's words are quoted line by line before the buttons" do
    blocks = Slack::Messages::WholeCard.build(rich: false, title: "T", subtitle: "S", body: "one\ntwo", quoted: true, actions: [ BUTTON ])

    assert_equal %w[section context divider section actions], blocks.pluck(:type)
    assert_equal "> one\n> two", blocks.fourth.dig(:text, :text)
  end
end
