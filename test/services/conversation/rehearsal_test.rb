require "test_helper"

class Conversation::RehearsalTest < ActiveSupport::TestCase
  RELEASE_RUN = "https://app.northflank.com/t/shop/project/web/workflows/release/runs/412".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_TERMINAL,
                                         prompt_version: "test", model: "gpt-4o")
    @result = run.results.create!(workspace: @workspace, scenario: "release", title: "Release")
    @model = FirefightAi::ModelChoice.new(model: "gpt-4o")
    # Every reply below is scripted, so the key is never sent anywhere.
    RubyLLM.config.stubs(:openai_api_key).returns("sk-test")
  end

  test "replays a chat on the real loop, answering every call from the record and the confirmation as the person did" do
    script(
      call("search_runbooks", "query" => "release"),
      call("run_runbook", "runbook" => "release", "intent" => "Start the production release"),
      reply("The release is running, see #{RELEASE_RUN}. I will watch it.")
    )

    replay = Conversation::Rehearsal.replay!(release_case(decisions: [ Conversation::BenchCase::DECISION_APPROVE ]), result: @result, model: @model)
    calls = replay.transcript.calls

    assert_equal %w[search_runbooks run_runbook], calls.map(&:name)
    assert_equal "Runbook release: tag, then run the Northflank release workflow.", calls.first.result
    assert_equal Chat::APPROVAL_APPROVED, calls.last.approval
    assert_equal "Started run 412 at #{RELEASE_RUN}", calls.last.result
    assert_equal 1, replay.transcript.confirmations.size
    assert_empty replay.transcript.unneeded_confirmations
    assert replay.transcript.cites_any?([ RELEASE_RUN ])
    assert_equal 3, replay.turns_used
    assert_equal @result, replay.chat.owner
  end

  test "a confirmation the person turned down is answered as a denial, and the call never runs" do
    script(call("run_runbook", "runbook" => "release", "intent" => "Start it"), reply("Understood, I left the release alone."))

    replay = Conversation::Rehearsal.replay!(release_case(decisions: [ Conversation::BenchCase::DECISION_DENY ]), result: @result, model: @model)

    assert_equal Chat::APPROVAL_DENIED, replay.transcript.calls.sole.approval
    refute replay.transcript.called?("run_runbook")
  end

  test "a confirmation nobody answered waits, and the next thing the person says moves past it" do
    script(call("run_runbook", "runbook" => "release", "intent" => "Start it"), reply("Here is where things stand."))

    replay = Conversation::Rehearsal.replay!(release_case(decisions: [], turns: [ "release to production", "actually, what is running now?" ]), result: @result, model: @model)

    assert_equal Chat::APPROVAL_WITHDRAWN, replay.transcript.calls.sole.approval
    assert_equal [ "Here is where things stand." ], replay.transcript.replies
  end

  test "a read through a tool that confirms changes runs at once, and a call nothing scripted finds nothing and is counted" do
    script(
      call("northflank_api_request", "method" => "GET", "path" => "/v1/projects/web/workflows/release/runs"),
      call("northflank_api_request", "method" => "GET", "path" => "/v1/projects/web/services"),
      reply("Run 412 failed at the migrate step.")
    )

    replay = Conversation::Rehearsal.replay!(release_case(decisions: []), result: @result, model: @model)
    first, second = replay.transcript.calls

    assert_nil first.approval
    assert_match "migrate", first.result
    assert_equal Conversation::BenchCase::NOTHING_FOUND, second.result
    assert_equal 1, replay.transcript.not_recorded
    assert_empty replay.chat.tool_calls.where(failed: true)
  end

  test "an answer after reading a connected system goes out as written, as it does live" do
    script(
      call("northflank_api_request", "method" => "GET", "path" => "/v1/projects/web/workflows/release/runs"),
      reply("Run 412 failed at the migrate step.")
    )

    replay = Conversation::Rehearsal.replay!(release_case(decisions: []), result: @result, model: @model)

    refute replay.chat.messages.exists?(nudge: true)
    assert_equal [ "Run 412 failed at the migrate step." ], replay.transcript.replies
  end

  # On the first real bench run a replay handed every tool over up front and open_tools said groups had nothing
  # connected, so models opened groups again and again and said tools they held were missing.
  # With specialists forced off, since in auto a chat past the budget asks them instead (Chat::Specialists.ask?).
  test "past the budget a chat holds only its own tools until open_tools opens the group a tool sits in, as it does live" do
    FirefightAi.stubs(:tool_search?).returns(false)
    FirefightAi.configuration.stubs(:held_tools_budget).returns(0)
    FirefightAi.configuration.stubs(:specialists).returns(:off)
    bench_case = build("tools" => [
      { "name" => "open_tools", "description" => "Opens groups", "base" => true },
      { "name" => "read_run", "description" => "Reads a run", "reads" => true, "source" => "northflank" }
    ], "answers" => [ { "tool" => "read_run", "result" => "Run 412 failed." } ])
    script(call("read_run", {}), call("open_tools", "group" => "northflank"), call("read_run", {}), reply("Run 412 failed."))

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)
    first, opened, second = replay.transcript.calls

    assert_equal [ "use_skill", "open_tools", "update_theories" ], JSON.parse(JSON.parse(first.result)["error"][/\[.*\]/])
    assert_match "read_run: Reads a run (ready to call)", opened.result
    assert_equal "Run 412 failed.", second.result
  end

  # A replay measures what a live chat would do, so on a provider that searches tools itself the scenario's tools are
  # handed over as Chat::Tools.presented hands them live, Firefight's own in hand and every connected one deferred.
  test "where the model's provider searches tools, Firefight's own are in hand and connected ones wait to be searched for" do
    FirefightAi.stubs(:tool_search?).returns(true)
    bench_case = build("tools" => [
      { "name" => "open_tools", "description" => "Opens groups", "base" => true },
      { "name" => "search_runbooks", "description" => "Finds runbooks", "reads" => true },
      { "name" => "read_run", "description" => "Reads a run", "reads" => true, "source" => "northflank" }
    ], "answers" => [ { "tool" => "read_run", "result" => "Run 412 failed." } ])
    offered = nil
    RubyLLM::Provider.any_instance.stubs(:complete).with { |_messages, tools:, **| offered ||= tools.transform_values { |tool| tool.is_a?(RubyLLM::Tool::Deferred) } }
                     .returns(reply("Run 412 failed."))

    Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)

    assert_equal false, offered[:search_runbooks]
    assert_equal true, offered[:read_run]
    assert_equal false, offered[:open_tools], "open_tools stays, to say what exists that cannot be used"
  end

  # Opening a group changed the tool list, which comes first in what a provider caches, so each opening wrote the whole
  # cached front again. A replay holds every tool from the start when they fit, as Chat::Tools.presented does live.
  test "where the provider does not search and the tools fit, every tool is held from the start and the tool list never changes" do
    FirefightAi.stubs(:tool_search?).returns(false)
    bench_case = build("tools" => [
      { "name" => "open_tools", "description" => "Opens groups", "base" => true },
      { "name" => "read_run", "description" => "Reads a run", "reads" => true, "source" => "northflank" }
    ], "answers" => [ { "tool" => "read_run", "result" => "Run 412 failed." } ])
    offered = []
    RubyLLM::Provider.any_instance.stubs(:complete).with { |_messages, tools:, **| offered << tools.dup }
                     .returns(call("read_run", {})).then.returns(call("open_tools", "group" => "northflank")).then.returns(reply("Run 412 failed."))

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)

    assert_equal "Run 412 failed.", replay.transcript.calls.first.result
    assert_includes offered.first.keys, :read_run
    assert_equal [ offered.first.keys ], offered.map(&:keys).uniq
    assert offered.first[:open_tools].description.start_with?(Chat::Tools::Open::HOLDS)
  end

  test "open_tools lists the scenario's own groups as ready, never as not connected" do
    tool = Conversation::Rehearsal::OpenTools.new(groups: { "northflank" => [ Conversation::BenchCase.tool_from({ "name" => "api_read", "description" => "Reads" }) ] },
                                                  open: ->(_names) { [] })

    assert_match "northflank: Northflank's own tools, such as api_read (ready)", tool.description
    assert_no_match(/not granted|nothing connected/, tool.description)
    assert_equal "There is no group called code. The groups are: northflank.", tool.call(group: "code")
  end

  # Seen on the first real bench run, a watch Halon repaired still listed its old step, so Halon told the person the watch
  # was unreliable after fixing it.
  test "a watch Halon starts and repairs reads what it follows now, through the scenario's own answers" do
    bench_case = build("tools" => %w[start_watch repair_watch list_watches].map { |name| { "name" => name, "description" => name, "base" => true } } +
                                  [ { "name" => "run_history", "description" => "Runs", "reads" => true } ],
                       "answers" => [ { "tool" => "run_history", "match" => { "run" => "412" }, "result" => "Run 412 is running at migrate." } ])
    script(
      call("start_watch", "title" => "The release", "steps" => [ { "label" => "Release", "capability" => "run_history", "resource" => "web", "name" => "release" } ]),
      call("list_watches", {}),
      call("repair_watch", "watch" => "W1", "step" => "1", "run" => "412", "why" => "The run is in the shop project"),
      call("list_watches", {}),
      reply("Watching run 412.")
    )

    calls = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model).transcript.calls

    assert_match Conversation::Rehearsal::State::NOTHING, calls[0].result
    assert_match Conversation::Rehearsal::State::NOTHING, calls[1].result
    assert_match "Repaired step 1 of watch W1. It now reads: Run 412 is running at migrate.", calls[2].result
    assert_match "Run 412 is running at migrate.", calls[3].result
  end

  test "a plan Halon makes keeps the steps it marks" do
    state = Conversation::Rehearsal::State.new(Conversation::BenchCase::World.new(build))

    state.call("make_plan", "goal" => "Release", "steps" => [ { "description" => "Start it", "kind" => "change" }, { "description" => "Check it", "kind" => "check" } ])
    updated = state.call("update_plan", "step" => 1, "status" => "done", "note" => "Run 412 started.")

    assert_equal "Plan P1:\n1. Start it (done) Run 412 started.\n2. Check it (waiting)", updated
    assert_equal "Plan P1 finished: Released.", state.call("finish_plan", "outcome" => "Released.", "next_step" => "Shall I roll back?")
  end

  # Seen on the diagnosis of the bench, Halon asked "Shall I open the pull request?" and the scripted person never
  # answered, so a scenario that needs a yes in words could not be finished.
  test "a question in plain words is answered from what the person wants, and a turn that wants a no still hears one" do
    bench_case = build("turns" => [ { "said" => "checkout is failing", "refuses" => [ "/roll ?back/" ] },
                                    { "said" => "it is getting worse", "approves" => [ "/roll ?back/" ] } ],
                       "tools" => [ { "name" => "rollback", "description" => "Rolls back", "confirms" => true } ],
                       "answers" => [ { "tool" => "rollback", "result" => "Rolled back." } ])
    script(
      reply("Deploy d-77 broke it. Shall I roll back checkout?"), reply("Understood, I will keep watching."),
      reply("Errors keep climbing. Shall I roll back checkout now?"), reply("Rolling back.")
    )

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)
    said = replay.chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).order(:created_at).pluck(:content)

    assert_equal [ "checkout is failing", Conversation::BenchCase::Person::NO, "it is getting worse", Conversation::BenchCase::Person::YES ], said
  end

  test "a question nothing in the scenario answers ends the turn, as before" do
    script(reply("Which region do you mean?"))

    replay = Conversation::Rehearsal.replay!(build, result: @result, model: @model)

    assert_equal [ "go" ], replay.chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).pluck(:content)
  end

  test "the person answers in the order the scenario says: the turn's own words, then the whole chat's, then the next decision" do
    bench_case = build("person" => { "approves" => [ "/pull request/" ], "answers" => [ { "asked" => "/repository/", "say" => "larkspur/shop" } ],
                                     "otherwise" => "Use your judgement." },
                       "turns" => [ { "said" => "go", "decisions" => [ "deny" ], "answers" => [ { "asked" => "/region/", "say" => "Europe" } ] } ])
    person = bench_case.person
    turn = bench_case.turns.sole
    ask = ->(reply) { person.answer(reply, turn: turn, decisions: turn.decisions) }

    assert_equal "Europe", ask.call("Which region is slow?")
    assert_equal "larkspur/shop", ask.call("Which repository holds it?")
    assert_equal Conversation::BenchCase::Person::YES, ask.call("Shall I open the pull request?")
    assert_equal Conversation::BenchCase::Person::NO, ask.call("Want me to restart it?")
    assert_equal "Use your judgement.", ask.call("What do you think caused it?")
    assert_nil ask.call("It failed at the migrate step.")
  end

  # Seen on the diagnosis of the bench, use_skill answered "No skill fits this" in every replay.
  test "use_skill serves the real skills, a provider's once the scenario offers its tools, and opens the tools a skill names" do
    opened = []
    tools = Conversation::Rehearsal.as_offered(build("tools" => [
      { "name" => "northflank_api_request", "description" => "Calls the API", "source" => "northflank", "confirms" => true },
      { "name" => "search_activity", "description" => "Searches the activity log", "reads" => true }
    ])).tools
    skill = Conversation::Rehearsal::UseSkill.new(tools: tools, open: ->(names) { opened.concat(names) })

    assert_match "leaked_secret:", skill.description
    assert_match "northflank_", skill.description
    assert_no_match(/cloudflare_/, skill.description)
    steps = skill.call(skill: "leaked_secret")
    assert_equal Chat::Skill.find("leaked_secret").steps.lines.first, steps.lines.first
    assert_includes opened, "search_activity"
  end

  # Seen on the diagnosis of the bench, 73 calls opened tools the instructions name, such as what_changed, that the
  # scenario left out, and were told no such tool exists.
  test "a scenario holds the tools a live chat always has, and those a connected system brings once it connects one" do
    plain = Conversation::Rehearsal.as_offered(build)
    connected = Conversation::Rehearsal.as_offered(release_case(decisions: []))

    assert_equal %w[read_run use_skill what_changed], plain.tools.map(&:name)
    assert_includes connected.tools.map(&:name), "resource_status"
    assert_includes connected.tools.map(&:name), "run_key_query"
    assert_equal "Runbook release: tag, then run the Northflank release workflow.", Conversation::BenchCase::World.new(connected).peek("search_runbooks", {}).result
  end

  private

  def build(extra = {})
    Conversation::BenchCase.from_hash({ "title" => "Test", "context" => "You are acting for Sam.", "turns" => [ "go" ],
                                        "tools" => [ { "name" => "read_run", "description" => "Reads", "reads" => true } ] }.merge(extra), key: "test")
  end

  def release_case(decisions:, turns: [ "release to production" ])
    Conversation::BenchCase.from_hash({
      "title" => "Release",
      "context" => "You are acting for Sam, whose role in this workspace is member.",
      "turns" => turns.each_with_index.map { |said, index| { "said" => said, "decisions" => (decisions if index.zero?) }.compact },
      "tools" => [
        { "name" => "search_runbooks", "description" => "Find a runbook", "reads" => true,
          "parameters" => { "type" => "object", "properties" => { "query" => { "type" => "string" } }, "required" => [ "query" ] } },
        { "name" => "run_runbook", "description" => "Run a runbook", "confirms" => true,
          "parameters" => { "type" => "object", "properties" => { "runbook" => { "type" => "string" } }, "required" => [ "runbook" ] } },
        { "name" => "northflank_api_request", "description" => "Call the Northflank API", "source" => "northflank", "confirms" => true,
          "reads_when" => { "method" => [ "GET" ] },
          "parameters" => { "type" => "object", "properties" => { "method" => { "type" => "string" }, "path" => { "type" => "string" } } } }
      ],
      "answers" => [
        { "tool" => "search_runbooks", "result" => "Runbook release: tag, then run the Northflank release workflow." },
        { "tool" => "run_runbook", "match" => { "runbook" => "release" }, "result" => "Started run 412 at #{RELEASE_RUN}" },
        { "tool" => "northflank_api_request", "match" => { "path" => "/workflows\\/release\\/runs/" }, "result" => "Run 412 failed at step migrate." }
      ],
      "expect" => { "outcome" => "The release runs", "evidence" => [ RELEASE_RUN ] }
    }, key: "release")
  end

  def call(name, arguments)
    id = "call_#{SecureRandom.hex(4)}"
    llm_reply(content: "", tool_calls: { id => RubyLLM::ToolCall.new(id: id, name: name, arguments: arguments) }, finish_reason: :tool_calls)
  end

  def reply(text) = llm_reply(content: text)

  def script(*replies)
    first, *rest = replies
    stubbed = RubyLLM::Provider.any_instance.stubs(:complete).returns(first)
    rest.each { |reply| stubbed = stubbed.then.returns(reply) }
  end
end
