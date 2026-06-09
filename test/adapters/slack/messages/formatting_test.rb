require "test_helper"

class Slack::Messages::FormattingTest < ActiveSupport::TestCase
  include Slack::Messages

  test "converts double-asterisk bold to single-asterisk Slack bold" do
    assert_equal "*hello* world", Formatting.markdown_to_mrkdwn("**hello** world")
  end

  test "converts double-underscore bold to single-asterisk Slack bold" do
    assert_equal "*hello* world", Formatting.markdown_to_mrkdwn("__hello__ world")
  end

  test "converts markdown headers to bold lines" do
    input = "# Big header\n\n## Subheader\n\nbody"
    expected = "*Big header*\n\n*Subheader*\n\nbody"
    assert_equal expected, Formatting.markdown_to_mrkdwn(input)
  end

  test "converts markdown links to Slack link syntax" do
    input = "see [the docs](https://example.com/path) please"
    expected = "see <https://example.com/path|the docs> please"
    assert_equal expected, Formatting.markdown_to_mrkdwn(input)
  end

  test "leaves dash bullet lists intact" do
    input = "- one\n- two\n- three"
    assert_equal input, Formatting.markdown_to_mrkdwn(input)
  end

  test "handles real LLM catchup output" do
    input = <<~MD.strip
      - **What Happened:** DB IOPS dropped.
      - **Status:** Identified, investigating.
        - **Lead:** Uros
    MD

    expected = <<~MRK.strip
      - *What Happened:* DB IOPS dropped.
      - *Status:* Identified, investigating.
        - *Lead:* Uros
    MRK

    assert_equal expected, Formatting.markdown_to_mrkdwn(input)
  end

  test "returns empty string when input is nil" do
    assert_equal "", Formatting.markdown_to_mrkdwn(nil)
  end
end
