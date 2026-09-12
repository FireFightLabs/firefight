require "test_helper"

class Slack::Messages::InvestigationBriefingTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  test "the message opens with a title and a divider above the body" do
    blocks = build(pack)

    assert_equal "section", blocks.first[:type]
    assert_match(/:mag:  \*What I know about INC-001\*/, blocks.first[:text][:text])
    assert_equal "divider", blocks.second[:type]
  end

  test "the incident's state reads on one field line" do
    text = section_texts(build(pack)).find { |section| section.include?("*Severity:*") }

    assert_equal "*Severity:* Critical  ·  *Status:* Investigating  ·  *Type:* Outage", text
  end

  test "the type is left out when the incident has none" do
    text = section_texts(build(pack(type: nil))).find { |section| section.include?("*Severity:*") }

    assert_not_includes text, "Type:"
  end

  test "people are mentioned so they can be reached from the message" do
    text = section_texts(build(pack)).find { |section| section.include?("*Lead:*") }

    assert_equal "*Lead:* <@U1>  ·  *Communications Lead:* <@U2>", text
  end

  test "someone with no platform account is named in bold rather than a broken mention" do
    facts = pack
    facts["incident"]["lead"] = { "name" => "Ada Agent", "platform_user_id" => nil }

    text = section_texts(build(facts)).find { |section| section.include?("*Lead:*") }

    assert_includes text, "*Lead:* *Ada Agent*"
  end

  test "alerts list their provider fields under the title" do
    text = section_texts(build(pack)).find { |section| section.start_with?("*Alerts*") }

    assert_includes text, "• Grafana: Pool exhausted (firing)"
    assert_includes text, "service=checkout"
  end

  test "alert text from a provider cannot page the channel" do
    facts = pack
    facts["alerts"].first["title"] = "<!channel> everyone look"

    text = section_texts(build(facts)).find { |section| section.start_with?("*Alerts*") }

    assert_includes text, "&lt;!channel&gt;"
    assert_not_includes text, "<!channel>"
  end

  test "the alert list stops at its ceiling and says what it held back" do
    facts = pack
    rows = Slack::Messages::InvestigationBriefing::ALERT_ROWS
    facts["alerts"] = Array.new(rows + 2) { |index| alert_facts(title: "Alert #{index}") }
    facts["alerts_held_back"] = 7

    text = section_texts(build(facts)).find { |section| section.start_with?("*Alerts*") }

    assert_includes text, "_9 more alerts not shown_",
                    "the two the message dropped are counted on top of the seven the pack dropped"
  end

  test "past incidents carry what was found last time" do
    text = section_texts(build(pack)).find { |section| section.start_with?("*Seen before") }

    assert_includes text, "*INC-003* Image upload broken"
    assert_includes text, "Finding: The pool was sized for one worker."
  end

  test "empty groups are left out rather than rendered as headings with nothing under them" do
    sections = section_texts(build(pack(alerts: [], runbooks: [], past_incidents: [])))

    assert_empty sections.select { |section| section.start_with?("*Alerts*", "*Runbooks", "*Seen before") }
  end

  test "the message stays inside Slack's block ceiling" do
    facts = pack
    facts["alerts"] = Array.new(50) { |index| alert_facts(title: "Alert #{index}") }
    facts["past_incidents"] = Array.new(50) { |index| { "identifier" => "INC-#{index}", "name" => "Old" } }

    assert_operator build(facts).size, :<=, 50
  end

  test "the fallback text says the same thing as the blocks" do
    text = Slack::Messages::InvestigationBriefing.fallback_text(incident: @incident, seed_pack: pack)

    assert_equal "What I know about INC-001: 1 alert, 1 similar past incident.", text
  end

  private

  def build(seed_pack)
    Slack::Messages::InvestigationBriefing.build(incident: @incident, seed_pack: seed_pack)
  end

  def section_texts(blocks)
    blocks.select { |block| block[:type] == "section" }.map { |block| block[:text][:text] }
  end

  def pack(type: "Outage", alerts: nil, runbooks: nil, past_incidents: nil)
    {
      "gathered_at" => Time.current.iso8601,
      "incident" => {
        "identifier" => "INC-001", "name" => "Database connection pool exhausted",
        "summary" => "Production database hitting max connections", "severity" => "Critical",
        "status" => "Investigating", "type" => type,
        "lead" => { "name" => "Alice", "platform_user_id" => "U1" },
        "roles" => [ { "role" => "Communications Lead",
                       "member" => { "name" => "Bob", "platform_user_id" => "U2" } } ]
      },
      "alerts" => alerts || [ alert_facts ],
      "alerts_held_back" => 0,
      "runbooks" => runbooks || [ { "name" => "Pool triage", "summary" => "What to check." } ],
      "past_incidents" => past_incidents || [
        { "identifier" => "INC-003", "name" => "Image upload broken", "resolved_at" => "2026-09-01T10:00:00Z",
          "finding" => "The pool was sized for one worker." }
      ]
    }
  end

  def alert_facts(title: "Pool exhausted")
    {
      "source" => "Grafana", "title" => title, "fingerprint" => "pool", "status" => "firing",
      "received_at" => "2026-09-12T09:40:00Z", "last_seen_at" => "2026-09-12T09:45:00Z",
      "fields" => { "title" => title, "service" => "checkout" }
    }
  end
end
