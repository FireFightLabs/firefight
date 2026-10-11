require "test_helper"

# A scenario offers a handful of tools, and a real workspace a few hundred. With HALON_BENCH_BIG_WORKSPACE=on every
# replay faces a large workspace's connections beside its own, built from the tool definitions Firefight keeps, which
# never answer for the scenario, so a run measures how Halon picks among them, with specialists or without.
class Conversation::BenchWorkspaceTest < ActiveSupport::TestCase
  setup do
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_TERMINAL,
                                         prompt_version: "test", model: "gpt-4o")
    @result = run.results.create!(workspace: workspaces(:slack_workspace_one), scenario: "release", title: "Release")
    @model = FirefightAi::ModelChoice.new(model: "gpt-4o")
    RubyLLM.config.stubs(:openai_api_key).returns("sk-test")
    @offered = []
  end

  test "the menu is the one its sources build, a few hundred tools across a real workspace's providers, in the order its seed fixes" do
    built = Conversation::BenchWorkspace.build

    assert_equal built, YAML.safe_load_file(Conversation::BenchWorkspace::TOOLS), "run bin/rails halon:bench_big_workspace"
    assert_equal built, Conversation::BenchWorkspace.build
    assert_operator built.size, :>=, 200
    assert_equal %w[aws cloudflare datadog github linear northflank notion opsgenie planetscale postgresql sentry], built.map { |tool| tool["source"] }.uniq.sort
    assert_not_equal built.map { |tool| tool["name"] }.sort, built.map { |tool| tool["name"] }, "the seed shuffles the menu"
    kinds = built.map { |tool| Chat::Specialists.of_provider(tool["source"]) }.uniq.compact.sort
    assert_equal %w[cloud code databases deploys observability on_call tickets], kinds
  end

  test "switched on, a replay offers the big workspace beside its own tools, the scenario's own definitions win, and an extra answers as unscripted" do
    Conversation::BenchWorkspace.stubs(:on?).returns(true)
    FirefightAi.configuration.stubs(:specialists).returns(:off)
    FirefightAi.stubs(:tool_search?).returns(false)
    script(call("open_tools", "group" => "notion", "tools" => %w[notion_notion_search northflank_read_run]),
           call("notion_notion_search", "query" => "release"), call("northflank_read_run", {}), reply("Run 412 failed."))

    replay = Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)
    _opened, searched, own = replay.transcript.calls

    assert_equal Conversation::BenchCase::NOTHING_FOUND, searched.result
    assert_equal "Run 412 failed at migrate.", own.result
    assert_equal 1, replay.transcript.not_recorded
    offered = Conversation::Rehearsal.as_offered(bench_case).tools
    assert_operator offered.size, :>, 200
    assert_equal 1, offered.count { |tool| tool.name == "northflank_read_run" }
    assert_includes @offered.first, :open_tools
    assert_not_includes @offered.first, :github_pr_lookup, "past the held tools budget the menu is opened group by group"
  end

  test "switched on, auto asks specialists since the workspace's tools do not fit, and Halon faces ask_specialist instead of the menu" do
    Conversation::BenchWorkspace.stubs(:on?).returns(true)
    FirefightAi.stubs(:tool_search?).returns(false)
    script(reply("Run 412 failed."))

    Conversation::Rehearsal.replay!(bench_case, result: @result, model: @model)

    assert_includes @offered.first, :ask_specialist
    assert_not_includes @offered.first, :github_pr_lookup
    assert_not_includes @offered.first, :notion_notion_search
  end

  test "a run records the big workspace in its label and its prompt version" do
    plain = Conversation::BenchWorkspace.version("abc")
    Conversation::BenchWorkspace.stubs(:on?).returns(true)

    assert_equal "abc", plain
    assert_match(/\Aabc\+big-\h{8}\z/, Conversation::BenchWorkspace.version("abc"))
    assert_equal "nightly, big workspace", Conversation::BenchWorkspace.label("nightly")
    assert_equal "big workspace", Conversation::BenchWorkspace.label(nil)
  end

  private

  def bench_case
    Conversation::BenchCase.from_hash({
      "title" => "Release", "context" => "You are acting for Sam.", "turns" => [ "how did the release go?" ],
      "tools" => [ { "name" => "open_tools", "description" => "Opens groups", "base" => true },
                   { "name" => "northflank_read_run", "description" => "Reads a run", "reads" => true, "source" => "northflank" } ],
      "answers" => [ { "tool" => "northflank_read_run", "result" => "Run 412 failed at migrate." } ]
    }, key: "release")
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
