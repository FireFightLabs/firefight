require "test_helper"

class ResourceMap::LogMinerTest < ActiveSupport::TestCase
  MINER = ResourceMap::LogMiner

  test "values are masked: times, emails, query strings, ids, hex, addresses, quoted values and numbers" do
    {
      "2026-10-06T10:42:01.123Z GET /orders" => "<TIME> GET /orders",
      "06/Oct/2026:10:42:01 +0000 served" => "<TIME> served",
      "at 10:42:01 started" => "at <TIME> started",
      "mail to ada@example.com failed" => "mail to <EMAIL> failed",
      "GET /search?q=shoes&page=2 200" => "GET /search?<QUERY> <NUM>",
      "order 3f2b9c1e-8d4a-4c1b-9e2f-7a6b5c4d3e2f shipped" => "order <UUID> shipped",
      "commit 9fceb02d0ae598e95dc970b74767f19372d61af8 deployed" => "commit <HEX> deployed",
      "pointer 0x7ffd5e8c at fault" => "pointer <HEX> at fault",
      "from 10.0.12.7:5432 refused" => "from <IP> refused",
      "from fe80::1ff:fe23:4567:890a" => "from <IP>",
      %(user "ada lovelace" signed in) => "user <QUOTED> signed in",
      "user 'ada' signed in" => "user <QUOTED> signed in",
      "took 412.5 ms for 3 rows" => "took <NUM> ms for <NUM> rows"
    }.each do |line, masked|
      assert_equal masked, MINER.masked(line), line
    end
  end

  test "no credential the scrubber knows survives into a pattern, and the samples cover every kind it knows" do
    assert_equal Chat::SecretFree::SECRET_PATTERNS.keys.sort, SecretSamples::SAMPLES.keys.sort

    lines = SecretSamples::SAMPLES.flat_map { |name, secret| [ "auth with #{secret} for #{name}", "ERROR token #{secret} rejected" ] }
    patterns = MINER.mine(lines)

    SecretSamples::SAMPLES.each do |name, secret|
      secret.split(/\s+/).reject { |part| part.size < 12 || part.start_with?("-----") }.each do |part|
        assert(patterns.none? { |pattern| pattern.template.include?(part) }, "#{name} survived")
      end
    end
    SecretSamples::SAMPLES.each do |name, secret|
      assert_includes MINER.masked("auth with #{secret}"), "[REDACTED:#{name}]"
    end
  end

  test "lines that differ in a value are one pattern, and lines of another shape are another" do
    lines = [
      "GET /orders 200 in 12 ms", "GET /orders 200 in 40 ms", "GET /orders 500 in 3001 ms",
      "user ada logged in", "user grace logged in", "user linus logged in",
      "worker started"
    ]

    patterns = MINER.mine(lines)

    assert_equal [ [ "GET /orders <NUM> in <NUM> ms", 3 ], [ "user <*> logged in", 3 ], [ "worker started", 1 ] ],
                 patterns.map { |pattern| [ pattern.template, pattern.lines ] }
  end

  test "the same lines in any order give the same patterns" do
    lines = 40.times.map { |index| [ "user u#{index % 7} logged in", "job #{index} done", "cache miss for key k#{index % 3}", "ERROR timeout on db#{index % 2}" ][index % 4] }
    first = MINER.mine(lines)

    5.times do |seed|
      assert_equal first, MINER.mine(lines.shuffle(random: Random.new(seed)))
    end
  end

  test "an error or warning line marks its pattern, an error outranking a warning" do
    patterns = MINER.mine([ "db: WARN slow query 1", "db: ERROR slow query 2", "level=error request failed", "plain line" ]).index_by(&:template)

    assert_equal "error", patterns["db: <*> slow query <NUM>"].level
    assert_equal "error", patterns["level=error request failed"].level
    assert_nil patterns["plain line"].level
  end

  test "a line follows a known pattern when the tree would have grouped it there" do
    known = MINER.known_by([ "GET /orders <NUM> in <NUM> ms", "user <*> logged in" ])

    assert_equal "user <*> logged in", known.known(MINER.masked("user ada logged in"))
    assert_equal "GET /orders <NUM> in <NUM> ms", known.known(MINER.masked("GET /orders 503 in 9 ms"))
    assert_nil known.known(MINER.masked("disk full on /var"))
  end

  test "the lines of a logs answer leave out its header and the link back, and an answer in JSON gives its messages" do
    text = Integrations::Telemetry.logs_text([ Integrations::Telemetry::LogLine.new(at: Time.zone.parse("2026-10-06T10:00:00Z"), source: "web-1", text: "user ada logged in") ],
                                             asked: "web")
    result = Integrations::Telemetry.result(text, link: Integrations::Telemetry::Link.new(provider: "Northflank", url: "https://app.northflank.com/x"))
    assert_equal [ "web-1 user ada logged in" ], MINER.lines_of(result)

    json = { "content" => [ { "type" => "text", "text" => { "data" => [ { "attributes" => { "message" => "boom" } }, { "msg" => "bang", "level" => "info" } ] }.to_json } ] }
    assert_equal %w[boom bang], MINER.lines_of(json)
    assert_empty MINER.lines_of({ "content" => [ { "type" => "text", "text" => "No log lines matched web." } ] })
  end
end
