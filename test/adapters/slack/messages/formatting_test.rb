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

  test "a link whose address holds parentheses keeps its whole address" do
    input = "read [the page](https://en.wikipedia.org/wiki/Mutex_(computing)) first"

    assert_equal "read <https://en.wikipedia.org/wiki/Mutex_(computing)|the page> first", Formatting.markdown_to_mrkdwn(input)
  end

  test "bold markers inside an address are never read as bold, in a link or bare" do
    input = "**Opened** [PR #856](https://example.com/a__b__c) and https://example.com/x__y__z"

    assert_equal "*Opened* <https://example.com/a__b__c|PR #856> and https://example.com/x__y__z", Formatting.markdown_to_mrkdwn(input)
  end

  test "bold around a bare address still closes" do
    assert_equal "*see https://example.com/x*.", Formatting.markdown_to_mrkdwn("**see https://example.com/x**.")
  end

  test "a link inside bold is still a link" do
    assert_equal "*<https://github.com/acme/app/pull/856|PR #856>*", Formatting.markdown_to_mrkdwn("**[PR #856](https://github.com/acme/app/pull/856)**")
  end

  test "a link's label never carries a character that ends a Slack link early" do
    assert_equal "<https://example.com|a / b &gt; c>", Formatting.markdown_to_mrkdwn("[a | b > c](https://example.com)")
  end

  test "a link escaped on the way in stays escaped, since that is how outside text is kept from faking one" do
    escaped = Slack::Mrkdwn.escape("see <https://evil.example|bank>")

    assert_equal "see &lt;https://evil.example|bank&gt;", Formatting.markdown_to_mrkdwn(escaped)
  end

  test "the agent's words are escaped except the links it wrote, in either form" do
    input = "Opened [PR #856](https://github.com/acme/app/pull/856) & <https://example.com/a?b=1&c=2|the page>, not <!here>"

    assert_equal "Opened <https://github.com/acme/app/pull/856|PR #856> &amp; <https://example.com/a?b=1&amp;c=2|the page>, not &lt;!here&gt;",
                 Formatting.escaped_with_links(input)
  end

  test "a link written in markdown's angle brackets renders as a link" do
    assert_equal "see <https://example.com/x>", Formatting.markdown_to_mrkdwn("see <https://example.com/x>")
  end

  test "Slack's own link form becomes a markdown link for text Slack reads as markdown" do
    input = "Opened <https://github.com/acme/app/pull/856|PR #856>, see <https://example.com> and <@U123>"

    assert_equal "Opened [PR #856](https://github.com/acme/app/pull/856), see <https://example.com> and <@U123>", Formatting.mrkdwn_links_to_markdown(input)
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
end
