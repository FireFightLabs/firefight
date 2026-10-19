require "test_helper"

# The bench replays a scenario the way the deployment runs Halon, so the same code is measured both ways: with
# specialists off Halon reads a connected system itself, and on it asks the specialist for that kind, which reads the
# scenario's world, only reads, and reports with the lines and links Halon cites.
class Conversation::RehearsalSpecialistsTest < ActiveSupport::TestCase
  INSIGHTS = "orders/main: open connections 498 of 500 since 13:39. https://app.planetscale.com/larkspur/orders/main/insights".freeze

  setup do
    workspace = workspaces(:slack_workspace_one)
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_TERMINAL,
                                         prompt_version: "test", model: "gpt-4o")
    @result = run.results.create!(workspace: workspace, scenario: "connections", title: "Connections")
    @model = FirefightAi::ModelChoice.new(model: "gpt-4o")
    # Every reply below is scripted, so the key is never sent anywhere.
    RubyLLM.config.stubs(:openai_api_key).returns("sk-test")
    FirefightAi.stubs(:tool_search?).returns(false)
    FirefightAi.configuration.stubs(:held_tools_budget).returns(1_000_000)
    @offered = []
  end

  test "in auto a scenario whose tools fit the budget is replayed as today, with Halon reading the connected system itself" do
    script(call("planetscale_get_insights", "database" => "orders"), reply("orders is at 498 of 500 connections."))

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)

    assert_equal [ "planetscale_get_insights" ], replay.transcript.calls.map(&:name)
    assert_includes @offered.first, :planetscale_get_insights
    assert_not_includes @offered.first, :ask_specialist
  end

  test "with specialists on Halon asks the databases specialist, which reads the world, reports its lines and links, and never writes" do
    FirefightAi.configuration.stubs(:specialists).returns(:on)
    script(
      call("ask_specialist", "asks" => [ { "domain" => "databases", "objective" => "Who holds orders' connections?" } ]),
      call("planetscale_api_request", "method" => "POST", "path" => "/branches"),
      call("planetscale_get_insights", "database" => "orders"),
      call("report_findings", "summary" => "orders is out of connections", "findings" => [
        { "claim" => "orders is at its limit", "lines" => [ "open connections 498 of 500 since 13:39" ],
          "links" => [ "https://app.planetscale.com/larkspur/orders/main/insights" ] }
      ]),
      reply("orders is at 498 of 500 connections, see https://app.planetscale.com/larkspur/orders/main/insights")
    )

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)
    halon, specialist = @offered

    assert_includes halon, :ask_specialist
    assert_not_includes halon, :planetscale_get_insights, "a connection's read is the specialist's"
    assert_includes specialist, :planetscale_get_insights
    assert_includes specialist, :report_findings
    assert_not_includes specialist, :open_tools

    calls = replay.transcript.calls
    assert_equal %w[ask_specialist planetscale_api_request planetscale_get_insights], calls.map(&:name)
    asked, refused, read = calls
    assert_equal [ nil, "The databases specialist", "The databases specialist" ], calls.map(&:by)
    assert_equal Conversation::Rehearsal::Specialists::ONLY_READS, refused.result, "a specialist never makes a change"
    assert_equal INSIGHTS, read.result
    assert_includes asked.result, "Shows: open connections 498 of 500 since 13:39"
    assert_includes asked.result, "Link: https://app.planetscale.com/larkspur/orders/main/insights"
    assert_includes replay.transcript.to_text, "The databases specialist, for the agent, called planetscale_get_insights"
    assert replay.transcript.cites_any?([ "orders/main/insights" ])
  end

  # Seen on the big workspace bench, the only tool that read Cloudflare's rules was its script tool, which no specialist
  # held, so nobody looked. Its read guard shows a call made as method and path reads, so the cloud specialist reads
  # through it, the scenario answering the script Firefight writes for that call.
  test "a specialist reads through a guarded general tool in its reading shape, answered as the scenario answers that request" do
    FirefightAi.configuration.stubs(:specialists).returns(:on)
    bench_case = Conversation::BenchCase.from_hash({
      "title" => "Rules", "context" => "You are acting for Sam.", "turns" => [ "why are big carts blocked?" ],
      "tools" => [ { "name" => "open_tools", "description" => "Opens groups", "base" => true },
                   { "name" => "cloudflare_execute", "description" => "Runs a script against the Cloudflare API", "confirms" => true, "source" => "cloudflare",
                     "request" => "code", "parameters" => { "type" => "object", "properties" => { "code" => { "type" => "string" } } } } ],
      "answers" => [ { "tool" => "cloudflare_execute", "match" => { "code" => "/rulesets/" }, "result" => "Rule body-size-limit blocks bodies over 64 KB since 14:02." } ]
    }, key: "rules")
    script(
      call("ask_specialist", "asks" => [ { "domain" => "cloud", "objective" => "What blocks large checkout requests?" } ]),
      call("cloudflare_execute", "method" => "GET", "path" => "/zones/7c1e/rulesets"),
      call("report_findings", "summary" => "A rule blocks big bodies", "findings" => [
        { "claim" => "A size rule blocks big carts", "lines" => [ "Rule body-size-limit blocks bodies over 64 KB since 14:02." ] }
      ]),
      reply("A Cloudflare rule blocks bodies over 64 KB since 14:02.")
    )

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)
    read = replay.transcript.calls.find { |each| each.by }

    assert_includes @offered.second, :cloudflare_execute
    assert_equal "Rule body-size-limit blocks bodies over 64 KB since 14:02.", read.result
    assert_equal "/zones/7c1e/rulesets", read.arguments["path"], "answered through the script Firefight writes for that read"
  end

  # The page and a thread list what Halon read under each answer, so a replay's judge reads the same list and citing
  # counts a link there as it counts one in the words.
  test "what an answer lists as read counts as citing, and the judge reads the list, while the line saying the next step never shows" do
    script(call("planetscale_get_insights", "database" => "orders"), reply("orders is at 498 of 500 connections.\n[next step: none]"))

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)

    assert_equal [ "orders is at 498 of 500 connections." ], replay.transcript.replies
    assert replay.transcript.cites_any?([ "orders/main/insights" ]), "the source under the answer links the insights page"
    assert_includes replay.transcript.to_text, "Listed under that answer as read: Planetscale get insights https://app.planetscale.com/larkspur/orders/main/insights"
  end

  # Written before Halon could read a Northflank workflow's runs itself, the scenario now holds them, so following the
  # release by its run is a fair ask.
  test "the release scenario's world answers the workflow's own runs, as the run moves from running to failed" do
    scenario = Conversation::BenchCase.scenario("release_watch_followed_nothing")
    world = Conversation::BenchCase::World.new(scenario)

    assert scenario.tool("northflank_workflow_runs")&.reads
    assert_match "running since 14:19", world.answer!("northflank_workflow_runs", { "workflow" => "release", "run" => "4182" }).result
    assert_match "failed at 14:26", world.answer!("northflank_workflow_runs", { "workflow" => "release", "run" => "4182" }).result
  end

  # Seen in a chat, Halon was asked to push a commit addressing a pull request's review, the code specialist read the
  # review, and every try at the change went back to Halon because only its own read backs one and every read of the
  # code host was the specialist's. A replay holds Halon to the same rule, and Halon loads the read the specialist made,
  # makes it itself and goes ahead.
  # Seen in a real chat, a model told to load the specialist's read by name never did. The refusal hands it the read,
  # so its next step makes it.
  test "a change backed only by a specialist goes back to Halon with the specialist's read in hand, which it makes and then asks the person" do
    FirefightAi.configuration.stubs(:specialists).returns(:on)
    script(
      call("ask_specialist", "asks" => [ { "domain" => "databases", "objective" => "Who holds orders' connections?" } ]),
      call("planetscale_get_insights", "database" => "orders"),
      call("report_findings", "summary" => "orders is out of connections", "findings" => [
        { "claim" => "orders is at its limit", "lines" => [ "open connections 498 of 500 since 13:39" ] }
      ]),
      call("open_tools", "group" => "planetscale", "tools" => [ "planetscale_api_request" ]),
      call("planetscale_api_request", "method" => "POST", "path" => "/branches", "intent" => "Raise the limit",
           "because" => [ "ask_specialist databases: orders is at 498 of 500" ]),
      call("planetscale_get_insights", "database" => "orders"),
      call("planetscale_api_request", "method" => "POST", "path" => "/branches", "intent" => "Raise the limit",
           "because" => [ "planetscale_get_insights: open connections 498 of 500 since 13:39" ]),
      reply("Raised it.")
    )

    replay = Conversation::Rehearsal.replay!(bench_case(decisions: [ Conversation::BenchCase::DECISION_APPROVE ]), result: @result, model: @model)
    calls = replay.transcript.calls.reject(&:by)

    assert_equal %w[ask_specialist open_tools planetscale_api_request planetscale_get_insights planetscale_api_request], calls.map(&:name)
    _asked, _opened_change, bounced, read, change = calls
    assert bounced.result.start_with?(Chat::Tools::LookFirst::BOUNCE), "a specialist's report does not back a change"
    assert_includes bounced.result, format(Chat::Tools::LookFirst::LOADED, reads: "planetscale_get_insights")
    assert_equal INSIGHTS, read.result
    assert_equal Chat::APPROVAL_APPROVED, change.approval
    assert_equal "Created branch raise-limit.", change.result
    assert_includes @offered.last, :planetscale_get_insights
  end

  # A provider whose every tool reads has no group of Halon's own until a specialist reads through it, and a read the
  # specialist made opens by name all the same.
  test "a read a specialist made opens by name though its provider has no tool of Halon's own" do
    FirefightAi.configuration.stubs(:specialists).returns(:on)
    script(
      call("ask_specialist", "asks" => [ { "domain" => "databases", "objective" => "Who holds orders' connections?" } ]),
      call("planetscale_get_insights", "database" => "orders"),
      call("report_findings", "summary" => "orders is out of connections", "findings" => [
        { "claim" => "orders is at its limit", "lines" => [ "open connections 498 of 500 since 13:39" ] }
      ]),
      call("open_tools", "group" => "planetscale", "tools" => [ "planetscale_get_insights" ]),
      reply("orders is at its limit.")
    )
    reads_only = Conversation::BenchCase.from_hash({
      "title" => "Connections", "context" => "You are acting for Sam.", "turns" => [ "why is orders refusing connections?" ],
      "tools" => [ { "name" => "open_tools", "description" => "Opens groups", "base" => true },
                   { "name" => "planetscale_get_insights", "description" => "Query insights for a branch", "reads" => true, "source" => "planetscale" } ],
      "answers" => [ { "tool" => "planetscale_get_insights", "result" => INSIGHTS } ]
    }, key: "connections")

    replay = Conversation::Rehearsal.replay!(reads_only, result: @result, model: @model)

    assert_equal "planetscale_get_insights: Query insights for a branch (ready to call)", replay.transcript.calls.reject(&:by).last.result
  end

  test "the two ways have different prompt versions, so a bench run says which it measured" do
    FirefightAi.configuration.stubs(:specialists).returns(:off)
    off = Conversation::Bench.send(:prompt_version, @result.workspace, @model)
    FirefightAi.configuration.stubs(:specialists).returns(:on)
    on = Conversation::Bench.send(:prompt_version, @result.workspace, @model)
    FirefightAi.configuration.stubs(:specialists).returns(:auto)

    assert_not_equal off, on
    assert_equal "#{off}+auto-#{on}", Conversation::Bench.send(:prompt_version, @result.workspace, @model)
  end

  private

  def bench_case(decisions: [])
    Conversation::BenchCase.from_hash({
      "title" => "Connections", "context" => "You are acting for Sam, whose role in this workspace is admin.",
      "turns" => [ { "said" => "why is orders refusing connections?", "decisions" => decisions } ],
      "tools" => [
        { "name" => "open_tools", "description" => "Opens groups", "base" => true },
        { "name" => "planetscale_get_insights", "description" => "Query insights for a branch", "reads" => true, "source" => "planetscale",
          "parameters" => { "type" => "object", "properties" => { "database" => { "type" => "string" } } } },
        { "name" => "planetscale_api_request", "description" => "Call the PlanetScale API", "confirms" => true, "source" => "planetscale",
          "reads_when" => { "method" => [ "GET" ] },
          "parameters" => { "type" => "object", "properties" => { "method" => { "type" => "string" }, "path" => { "type" => "string" } } } }
      ],
      "answers" => [ { "tool" => "planetscale_get_insights", "result" => INSIGHTS },
                     { "tool" => "planetscale_api_request", "match" => { "method" => "POST" }, "result" => "Created branch raise-limit." } ]
    }, key: "connections")
  end

  def call(name, arguments)
    id = "call_#{SecureRandom.hex(4)}"
    llm_reply(content: "", tool_calls: { id => RubyLLM::ToolCall.new(id: id, name: name, arguments: arguments) }, finish_reason: :tool_calls)
  end

  def reply(text) = llm_reply(content: text)

  def script(*replies)
    first, *rest = replies
    stubbed = RubyLLM::Provider.any_instance.stubs(:complete).with { |_messages, tools:, **| @offered << tools.keys }.returns(first)
    rest.each { |each| stubbed = stubbed.then.returns(each) }
  end
end
