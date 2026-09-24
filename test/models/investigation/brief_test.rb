require "test_helper"

class Investigation::BriefTest < ActiveSupport::TestCase
  test "what someone said is kept with where it came from, and a time it cannot read is dropped" do
    brief = Investigation::Brief.from(
      { "symptom" => "  checkout   returns 500  ", "started_around" => "2026-09-24T14:05:00+02:00", "names" => [ "checkout", "", "checkout" ],
        "error_text" => "PoolExhausted" },
      source: Investigation::Brief::SOURCE_CHAT
    )

    assert_equal "checkout returns 500", brief["symptom"]
    assert_equal "2026-09-24T12:05:00Z", brief["started_around"]
    assert_equal [ "checkout" ], brief["names"]
    assert_equal Investigation::Brief::SOURCE_CHAT, brief["source"]
    assert_nil Investigation::Brief.from({ "started_around" => "since lunch" }, source: Investigation::Brief::SOURCE_CHAT)["started_around"]
  end

  test "nothing said is an empty brief, not one that only names its source" do
    assert_equal({}, Investigation::Brief.from({ "symptom" => " " }, source: Investigation::Brief::SOURCE_COMMAND))
  end
end
