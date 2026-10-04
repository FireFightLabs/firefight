require "test_helper"

class Integrations::Capabilities::AnswersTest < ActiveSupport::TestCase
  Answers = Integrations::Capabilities::Answers
  LINK = Integrations::Telemetry.link_line(Integrations::Telemetry::Link.new(provider: "Acme", url: "https://acme.example/q"))

  test "a connected tool's parameters decide which argument names are written, and one Firefight does not know is refused" do
    tool = Integration::Tool.new(name: "query", params_schema: { "properties" => { "query" => {}, "start_time" => {} } })

    assert_equal "start_time", Answers.named(tool, %w[from start_time])
    assert_equal({ "query" => "x" }, Answers.known!(tool, { "query" => "x" }, "Acme"))
    assert_match "takes its arguments in a way Firefight does not know (no limit)", assert_raises(Integrations::Capabilities::Unroutable) { Answers.known!(tool, { "limit" => 5 }, "Acme") }.message
    assert_nil Answers.properties(nil)
  end

  test "the time and limit asked are read once, the same way for every adapter" do
    assert_equal 30, Answers.minutes("minutes" => 30)
    assert_equal Integrations::Capabilities::MAX_MINUTES, Answers.minutes("minutes" => 10**9)
    assert_nil Answers.minutes("start" => "2026-09-01T00:00:00Z")
    assert_equal [ 20, 50, 10 ], [ Answers.limit({ "limit" => 20 }, 50), Answers.limit({}, 50), Answers.limit({}, 50, default: 10) ]
    assert_equal Time.utc(2026, 9, 1), Answers.time_of(1_788_220_800_000)
    assert_equal Time.utc(2026, 9, 1), Answers.time_of("2026-09-01T00:00:00Z")
  end

  test "an answer is read as data past the link Firefight added, and one in a shape nobody expected reaches the agent as it came" do
    result = { "content" => [ { "type" => "text", "text" => '{"rows": [1]}' }, { "type" => "text", "text" => LINK } ] }

    assert_equal({ "rows" => [ 1 ] }, Answers.data(result))
    assert_equal '{"rows": [1]}', Answers.text(result)
    assert_equal "https://acme.example/q", Answers.linked(result)
    assert_equal result, Answers.read(result, "acme") { |_body| raise KeyError }
    presented = Answers.read(result, "acme") { |body| Answers.presented(result, "#{body['rows'].size} rows") }
    assert_equal [ "1 rows", LINK ], presented["content"].map { |part| part["text"] }
  end
end
