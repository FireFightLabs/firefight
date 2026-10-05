require "test_helper"

class IncidentUpdate::MessageTextTest < ActiveSupport::TestCase
  test "a bullet glyph at the start of a line becomes a markdown list item" do
    text = "Findings so far:\n\n• Probing was observed.\n  • Nested detail\n• Requests returned 404."

    assert_equal "Findings so far:\n\n- Probing was observed.\n  - Nested detail\n- Requests returned 404.",
                 IncidentUpdate::MessageText.normalize(text)
  end

  test "bullets run together after a sentence are split onto their own lines" do
    text = "Findings so far: • Probing was observed. • Linear follow-up: FIR-105 https://linear.app/x/FIR-105"

    assert_equal "Findings so far:\n- Probing was observed.\n- Linear follow-up: FIR-105 https://linear.app/x/FIR-105",
                 IncidentUpdate::MessageText.normalize(text)
  end

  test "a bullet used as a separator inside a sentence is left alone" do
    text = "Checkout • Payments • Auth are degraded"

    assert_equal text, IncidentUpdate::MessageText.normalize(text)
  end

  test "markdown, plain prose and code blocks pass through unchanged" do
    text = "Rolled back.\n\n- Errors at baseline\n- [Dashboard](https://grafana.example/d/1)\n\n```\n• not a list\n```"

    assert_equal text, IncidentUpdate::MessageText.normalize(text)
  end

  test "windows line endings become plain newlines" do
    assert_equal "One\n- Two", IncidentUpdate::MessageText.normalize("One\r\n• Two")
  end

  test "nothing to normalize returns what it was given" do
    assert_nil IncidentUpdate::MessageText.normalize(nil)
    assert_equal "", IncidentUpdate::MessageText.normalize("")
  end

  test "the lead is the first line with its list or heading marker dropped, cut at a word when it runs long" do
    assert_equal "Findings so far.", IncidentUpdate::MessageText.lead("\nFindings so far.\n\n- Bursts at 01:30", limit: 200)
    assert_equal "Bursts at 01:30", IncidentUpdate::MessageText.lead("• Bursts at 01:30\n• All 404", limit: 200)
    assert_equal "Rolled back", IncidentUpdate::MessageText.lead("## Rolled back", limit: 200)
    assert_equal "Traffic came through…", IncidentUpdate::MessageText.lead("Traffic came through Cloudflare", limit: 22)
    assert_nil IncidentUpdate::MessageText.lead(" \n ", limit: 200)
    assert_nil IncidentUpdate::MessageText.lead(nil, limit: 200)
  end
end
