require "test_helper"

class Conversation::BenchCaseTest < ActiveSupport::TestCase
  # The five failures that started the bench, the nineteen scenarios of the stress test, the three habits the first
  # real run found in every model, the harder scenarios that tell a strong model from a cheap one, and the real chats
  # since that each found a way Halon was boxed in.
  FAILURES = %w[release_watch_followed_nothing slow_query_investigation_timed_out sticks_with_no duplicate_workspace_signup confirm_card_repeats_choices].freeze
  HABITS = %w[reads_without_asking general_read_when_no_tool repository_from_the_map].freeze
  CHATS = %w[review_fix_on_a_specialists_read change_only_reads_through_a_change].freeze
  # Habits of the answer itself, such as placing the charts it drew beside what they show.
  ANSWERS = %w[charts_sit_where_they_are_read].freeze

  test "every scenario reads, says what a good run reaches and what it does next, and names only tools it offers" do
    scenarios = Conversation::BenchCase.scenarios

    assert_equal FAILURES.size + 19 + HABITS.size + 12 + CHATS.size + ANSWERS.size, scenarios.size
    assert_empty (FAILURES + HABITS + CHATS + ANSWERS) - scenarios.map(&:key)
    assert_equal 19, scenarios.count { |scenario| scenario.key.start_with?("stress_") }
    assert_equal 12, scenarios.count { |scenario| scenario.key.start_with?("hard_") }
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

  test "an answer used up gives way to the next, and one that holds in another state answers once a change moved the world there" do
    bench_case = build(world: { "token" => "active" }, answers: [
      { "tool" => "read", "match" => { "path" => "/tokens/" }, "state" => { "token" => "revoked" }, "result" => "revoked" },
      { "tool" => "read", "times" => 1, "result" => "running" },
      { "tool" => "read", "result" => "failed" },
      { "tool" => "change", "match" => { "method" => "POST" }, "sets" => { "token" => "revoked" }, "result" => "Rotated." }
    ])
    world = Conversation::BenchCase::World.new(bench_case)

    assert_equal "running", world.answer!("read", { "path" => "/runs/1" }).result
    assert_equal "failed", world.answer!("read", { "path" => "/runs/1" }).result
    assert_equal "failed", world.answer!("read", { "path" => "/tokens/1" }).result
    assert_equal "Rotated.", world.answer!("change", { "method" => "POST" }).result
    assert_equal "revoked", world.peek("read", { "path" => "/tokens/1" }).result
  end

  # Seen on the diagnosis of the bench, a release run read as running through two tools, each with its own count, so
  # Halon was told running twice.
  test "two tools reading one run read one world, so the first read moves both on" do
    release = Conversation::BenchCase.scenario("release_watch_followed_nothing")
    world = Conversation::BenchCase::World.new(release)

    assert_match "running", world.answer!("run_history", { "run" => "4182" }).result
    assert_match "\"status\":\"failed\"", world.answer!("northflank_api_request", { "method" => "GET", "path" => "/v1/projects/shop/workflows/release/runs/4182" }).result
    assert_match "failed at 14:26", world.answer!("run_history", { "run" => "4182" }).result
  end

  # The harder scenarios answer a change by what it left, so a model that acts before reading sees its mistake.
  test "a rerun fails until the job reads the rotated password, and a rollback past a migration breaks every order" do
    invoices = Conversation::BenchCase.scenario("hard_05_early_detail_decides")
    rerun = { "method" => "POST", "path" => "/v1/projects/shop/jobs/invoices/runs" }
    world = Conversation::BenchCase::World.new(invoices)

    assert_match "failed", world.peek("northflank_api_request", rerun).result
    world.answer!("northflank_api_request", { "method" => "PATCH", "path" => "/v1/projects/shop/jobs/invoices/runtime-environment" })
    assert_match "succeeded", world.peek("northflank_api_request", rerun).result

    refunds = Conversation::BenchCase.scenario("hard_09_rollback_past_a_migration")
    world = Conversation::BenchCase::World.new(refunds)
    assert_match "refunds_controller.rb:58", world.peek("search_logs", { "resource" => "api" }).result
    world.answer!("rollback", { "resource" => "api", "to" => "d-497" })
    assert_match "Unknown column", world.peek("search_logs", { "resource" => "api" }).result
  end

  test "a tool's default answers what nothing recorded, and lists the tools it offers when asked to" do
    bench_case = build(tools: [ tool("open_tools", "default" => "Open already:\n%{tools}"), tool("read") ])
    world = Conversation::BenchCase::World.new(bench_case)

    assert_match "- read: Reads it", world.peek("open_tools", {}).result
    assert_nil world.peek("read", {})
  end

  test "a tool that reads like another answers what that one would, so two reads of the same deploys agree" do
    bench_case = build(tools: [ tool("what_changed", "reads_like" => "recent_deploys", "default" => "Nothing changed."), tool("recent_deploys") ],
                       answers: [ { "tool" => "recent_deploys", "match" => { "resource" => "checkout" }, "result" => "checkout d-77 at 14:05" } ])
    world = Conversation::BenchCase::World.new(bench_case)

    assert_equal "checkout d-77 at 14:05", world.peek("what_changed", { "resource" => "checkout" }).result
    assert_equal "Nothing changed.", world.peek("what_changed", { "resource" => "api" }).result
  end

  # Seen on the diagnosis of the bench, a scenario answered any GET with the same list and any script with "Done.".
  test "an answer to a general tool must say which requests it answers, and a call nothing answers finds nothing" do
    general = tool("api", "reads" => false, "confirms" => true, "reads_when" => { "method" => [ "GET" ] }, "request" => "path")

    error = assert_raises(Conversation::BenchCase::Invalid) { build(tools: [ general ], answers: [ { "tool" => "api", "match" => { "method" => "GET" }, "result" => "[]" } ]) }
    assert_equal "An answer to api must match its path, so it never answers a request it was not written for.", error.message

    bench_case = build(tools: [ general ], answers: [ { "tool" => "api", "match" => { "path" => "/runs/" }, "result" => "Run 4 failed." } ])
    assert_equal Conversation::BenchCase::NOTHING_FOUND, bench_case.unscripted("api", { "method" => "GET", "path" => "/audit" })
    assert_equal Conversation::BenchCase::NOTHING_CHANGED, bench_case.unscripted("api", { "method" => "POST", "path" => "/audit" })
  end

  test "every scenario's general tools have answers that each name the requests they answer" do
    Conversation::BenchCase.scenarios.each do |scenario|
      scenario.answers.each do |answer|
        field = scenario.tool(answer.tool).request
        assert answer.match.key?(field), "#{scenario.key} answers #{answer.tool} without matching its #{field}" if field
      end
    end
  end

  test "what the person wants, agrees to and turns down is read once for the chat and turn by turn" do
    bench_case = build(person: { "approves" => [ "/pull request/" ], "answers" => [ { "asked" => "/repository/", "say" => "larkspur/shop" } ], "otherwise" => "No idea." },
                       turns: [ { "said" => "go", "refuses" => [ "/roll ?back/" ], "sets" => { "errors" => "climbing" } } ])

    assert_equal [ "/pull request/" ], bench_case.person.approves
    assert_equal "larkspur/shop", bench_case.person.answers.sole.say
    assert_equal [ "/roll ?back/" ], bench_case.turns.sole.refuses
    assert_equal({ "errors" => "climbing" }, bench_case.turns.sole.sets)
  end

  # Every model read "workspace" as a Firefight workspace, so the scenario now says it is about the team's own app.
  test "the signup scenario is about the team's own app, never a Firefight workspace" do
    signup = Conversation::BenchCase.scenario("duplicate_workspace_signup")
    said = [ signup.title, signup.context, *signup.turns.map(&:said), signup.expect.outcome ].join(" ")

    assert_match "shop app", said
    assert_no_match(/workspace/i, [ signup.title, *signup.turns.map(&:said), signup.expect.outcome ].join(" "))
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

  test "written back as a scenario it reads the same, its world and its person included" do
    [ "sticks_with_no", "duplicate_workspace_signup" ].each do |key|
      bench_case = Conversation::BenchCase.scenario(key)

      again = Conversation::BenchCase.from_hash(bench_case.to_h, key: bench_case.key)

      assert_equal bench_case.to_h, again.to_h
    end
  end

  private

  def tool(name, extra = {})
    { "name" => name, "description" => "Reads it", "reads" => true }.merge(extra)
  end

  def build(answers: [], tools: [ tool("read"), tool("change", "reads" => false, "confirms" => true) ], turns: [ "go" ], world: {}, person: {})
    Conversation::BenchCase.from_hash({ "title" => "Test", "turns" => turns, "tools" => tools, "answers" => answers, "world" => world, "person" => person }, key: "test")
  end
end
