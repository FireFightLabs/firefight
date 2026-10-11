require "test_helper"

class FirefightAi::FactsTest < ActiveSupport::TestCase
  test "each part the facts hold is explained beside them, and a part a run does not have is not" do
    opening = FirefightAi::Facts.opening("Investigate this.", {
      "incident" => { "identifier" => "INC-001" }, "resources" => [ { "name" => "web" } ], "on_call" => { "pages_on_call" => true },
      "memories" => [], "handbook" => [ "Page \"Releases\"" ]
    })

    assert opening.start_with?("Investigate this.\n\nHow to read them:\n")
    assert_includes opening, FirefightAi::Facts::READING.fetch("resources")
    assert_includes opening, FirefightAi::Facts::READING.fetch("on_call")
    assert_includes opening, FirefightAi::Facts::READING.fetch("handbook")
    assert_not_includes opening, FirefightAi::Facts::READING.fetch("memories")
    assert_not_includes opening, FirefightAi::Facts::READING.fetch("past_incidents")
    assert_includes opening, "\"identifier\": \"INC-001\""
  end

  test "facts with nothing to explain are handed over as they are" do
    assert_equal "Run this check.\n\n{\n  \"check\": {}\n}\n", FirefightAi::Facts.opening("Run this check.", { "check" => {} })
  end

  test "what the old rules said of memory, the handbook, the map, past answers and an unattended run is where the run meets it" do
    reading = FirefightAi::Facts::READING
    assert_match "hunches to check against live results", reading.fetch("memories")
    assert_match "dispute it with dispute_memory", reading.fetch("memories")
    assert_match "propose the edit with propose_handbook_edit", reading.fetch("handbook")
    assert_match "the more specific one winning", reading.fetch("instructions")
    assert_match "get_resource_neighbours and traverse_resource_map", reading.fetch("resources")
    assert_match "a mistake to learn from rather than a lead", reading.fetch("past_incidents")
    assert_match "Load the on_call_alert skill with use_skill first", reading.fetch("on_call")
  end
end
