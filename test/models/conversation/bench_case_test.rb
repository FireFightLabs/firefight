require "test_helper"

class Conversation::BenchCaseTest < ActiveSupport::TestCase
  # The five failures that started the bench, the nineteen scenarios of the stress test, and the three habits the first
  # real run found in every model.
  FAILURES = %w[release_watch_followed_nothing slow_query_investigation_timed_out sticks_with_no duplicate_workspace_signup confirm_card_repeats_choices].freeze
  HABITS = %w[reads_without_asking general_read_when_no_tool repository_from_the_map].freeze

  test "every scenario reads, says what a good run reaches and what it does next, and names only tools it offers" do
    scenarios = Conversation::BenchCase.scenarios

    assert_equal FAILURES.size + 19 + HABITS.size, scenarios.size
    assert_empty (FAILURES + HABITS) - scenarios.map(&:key)
    assert_equal 19, scenarios.count { |scenario| scenario.key.start_with?("stress_") }
    scenarios.each do |scenario|
      assert scenario.expect.outcome.present?, "#{scenario.key} says nothing about the right outcome"
      assert scenario.expect.next_step.present?, "#{scenario.key} says nothing about the next step"
      assert scenario.shape.present?, "#{scenario.key} says nothing about the failure it comes from"
      assert scenario.context.start_with?("You are acting for "), "#{scenario.key} does not say who is asking the way a chat does"
    end
  end

  # Seen while writing them, a scenario's evidence named a link no answer returned, which no replay could ever cite.
  test "every scenario's evidence is something one of its answers returns" do
    Conversation::BenchCase.scenarios.each do |scenario|
      said = scenario.answers.map(&:result).join("\n").downcase
      scenario.expect.evidence.each { |text| assert_includes said, text.downcase, "#{scenario.key} expects #{text}, which no answer returns" }
    end
  end

  test "scenario copy keeps to the house style" do
    Conversation::BenchCase.scenarios.each do |scenario|
      [ scenario.title, scenario.shape, scenario.expect.outcome, scenario.expect.next_step ].each do |text|
        refute_match(/[—;]/, text, "#{scenario.key}: #{text}")
      end
    end
  end

  # A model asked which repository to look in when nothing in the scenario named it, and was marked down for it.
  test "a scenario whose tools need a repository gives it the way a chat finds it, on the map or in the catalog" do
    Conversation::BenchCase.scenarios.each do |scenario|
      needs = scenario.tools.any? { |tool| tool.parameters.to_h.dig("properties", "repository") }
      next unless needs

      found = scenario.answers.any? do |answer|
        %w[get_resource_map search_catalog search_handbook].include?(answer.tool) && answer.result.include?("larkspur/shop")
      end
      said = [ scenario.context, *scenario.turns.map(&:said) ].join(" ")
      assert found || said.include?("larkspur/shop"), "#{scenario.key} needs a repository and nothing a chat reads names it"
    end
  end

  test "every scenario's tools a chat opens are reached through open_tools, and its own tools are in hand from the start" do
    Conversation::BenchCase.scenarios.each do |scenario|
      next unless scenario.tool(Chat::Tools::Open.tool_name)

      assert scenario.tool(Chat::Tools::Open.tool_name).base, "#{scenario.key} must hold open_tools from the start"
      assert scenario.tools.any? { |tool| !tool.base }, "#{scenario.key} gives open_tools nothing to open"
    end
  end

  test "an answer matches a subset of the arguments without regard to case, and a pattern between slashes" do
    answer = Conversation::BenchCase.answer_from({ "tool" => "api", "match" => { "method" => "get", "path" => "/runs\\/41/" }, "result" => "ok" })

    assert answer.matches?("api", { "method" => "GET", "path" => "/v1/workflows/release/runs/412", "body" => {} })
    refute answer.matches?("api", { "method" => "POST", "path" => "/v1/workflows/release/runs/412" })
    refute answer.matches?("other", { "method" => "GET", "path" => "/runs/41" })
  end

  test "an answer used up gives way to the next, and one that waits on an earlier call answers only once it ran" do
    bench_case = build(answers: [
      { "tool" => "read", "match" => { "path" => "/tokens/" }, "after" => { "tool" => "change", "match" => { "method" => "POST" } }, "result" => "revoked" },
      { "tool" => "read", "times" => 1, "result" => "running" },
      { "tool" => "read", "result" => "failed" }
    ])
    used = Hash.new(0)

    first, index = bench_case.answer_for("read", { "path" => "/runs/1" }, used)
    used[index] += 1
    assert_equal "running", first.result
    assert_equal "failed", bench_case.answer_for("read", { "path" => "/runs/1" }, used).first.result
    assert_equal "failed", bench_case.answer_for("read", { "path" => "/tokens/1" }, used, [ [ "change", { "method" => "GET" } ] ]).first.result
    assert_equal "revoked", bench_case.answer_for("read", { "path" => "/tokens/1" }, used, [ [ "change", { "method" => "POST" } ] ]).first.result
  end

  test "a tool's default answers what nothing recorded, and lists the tools it offers when asked to" do
    bench_case = build(tools: [ tool("open_tools", "default" => "Open already:\n%{tools}"), tool("read") ])

    said = bench_case.answer_for("open_tools", {}, Hash.new(0)).first.result

    assert_match "- read: Reads it", said
    assert_nil bench_case.answer_for("read", {}, Hash.new(0))
  end

  test "a call is a read when its tool only reads or its arguments say so, and only a change waits for the person" do
    general = Conversation::BenchCase.tool_from(tool("api", "reads" => false, "confirms" => true, "reads_when" => { "method" => [ "GET" ] }))

    assert general.reads?({ "method" => "get" })
    refute general.asks?({ "method" => "GET" })
    assert general.asks?({ "method" => "DELETE" })
  end

  test "a case that names a tool it does not offer, or a decision nobody can make, is refused with the reason" do
    error = assert_raises(Conversation::BenchCase::Invalid) { build(answers: [ { "tool" => "missing", "result" => "x" } ]) }
    assert_equal "missing is not offered.", error.message

    error = assert_raises(Conversation::BenchCase::Invalid) { build(turns: [ { "said" => "go", "decisions" => [ "maybe" ] } ]) }
    assert_equal "A decision is approve or deny, not maybe.", error.message
  end

  test "written back as a scenario it reads the same" do
    bench_case = Conversation::BenchCase.scenario("sticks_with_no")

    again = Conversation::BenchCase.from_hash(bench_case.to_h, key: bench_case.key)

    assert_equal bench_case.to_h, again.to_h
  end

  private

  def tool(name, extra = {})
    { "name" => name, "description" => "Reads it", "reads" => true }.merge(extra)
  end

  def build(answers: [], tools: [ tool("read"), tool("change", "reads" => false, "confirms" => true) ], turns: [ "go" ])
    Conversation::BenchCase.from_hash({ "title" => "Test", "turns" => turns, "tools" => tools, "answers" => answers }, key: "test")
  end
end
