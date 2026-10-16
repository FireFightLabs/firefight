require "test_helper"

class Slack::EmojiTest < ActiveSupport::TestCase
  test "no two concepts share an emoji" do
    shortcodes = Slack::Emoji.constants.map { |name| Slack::Emoji.const_get(name) }

    assert_equal shortcodes.size, shortcodes.uniq.size
  end

  test "declared, escalated, reopened and a firing alert each look different, as do an approval and a refused pack" do
    assert_equal 4, [ Slack::Emoji::DECLARED, Slack::Emoji::ESCALATED, Slack::Emoji::REOPENED, Slack::Emoji::ALERT_FIRING ].uniq.size
    assert_not_equal Slack::Emoji::APPROVAL, Slack::Emoji::PACK_REFUSAL
  end
end
