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

  test "quoted markdown quotes every line and draws list markers as bullets" do
    input = "Findings so far:\n\n- Probing was **observed**\n  * Nested\n- See [FIR-105](https://linear.app/x/FIR-105)"
    expected = "> Findings so far:\n>\n> • Probing was *observed*\n>   • Nested\n> • See <https://linear.app/x/FIR-105|FIR-105>"

    assert_equal expected, Formatting.quoted_markdown(input)
  end

  test "quoted markdown leaves code blocks and bold text alone" do
    input = "Ran:\n```\n- not a bullet\n```\n*Bold* stays"

    assert_equal "> Ran:\n> ```\n> - not a bullet\n> ```\n> *Bold* stays", Formatting.quoted_markdown(input)
  end

  test "quoted markdown keeps a one line message as it was" do
    assert_equal "> Rolling back the deploy", Formatting.quoted_markdown("Rolling back the deploy")
  end

  test "a markdown link renders as a Slack link, its address keeping parentheses and losing a title" do
    assert_equal "See <https://en.wikipedia.org/wiki/Mars_(planet)|Mars> and <https://x.dev/a|the PR>",
                 Formatting.markdown_to_mrkdwn("See [Mars](https://en.wikipedia.org/wiki/Mars_(planet)) and [the PR](https://x.dev/a \"PR 1\")")
  end

  test "a link's label and address cannot break out of the link" do
    assert_equal "<https://x.dev/a|ab>", Formatting.markdown_to_mrkdwn("[a|b](https://x.dev/a)")
  end

  test "sections never drop a character, break at line ends and stay under the limit" do
    text = Array.new(400) { |index| "Line #{index} #{'y' * 30}" }.join("\n")

    sections = Formatting.sections(text)

    assert_operator sections.size, :>, 1
    assert sections.all? { |section| section.length <= Formatting::SECTION_TEXT_LIMIT }
    assert_equal text, sections.join("\n")
  end

  test "a line longer than a section breaks at a space, and a code block a break falls inside is closed and opened again" do
    long = ([ "word" ] * 1000).join(" ")
    assert_equal long, Formatting.sections(long).join(" ")

    code = "```\n#{Array.new(200) { |index| "puts #{index} #{'z' * 20}" }.join("\n")}\n```"
    sections = Formatting.sections(code)
    assert_operator sections.size, :>, 1
    assert sections.all? { |section| section.start_with?("```") && section.end_with?("```") }
  end
end
