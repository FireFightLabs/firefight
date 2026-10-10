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

  test "a read through a tool that confirms changes runs at once, and a call missing from the record is said to be" do
    script(
      call("northflank_api_request", "method" => "GET", "path" => "/v1/projects/web/workflows/release/runs"),
      call("northflank_api_request", "method" => "GET", "path" => "/v1/projects/web/services"),
      reply("Run 412 failed at the migrate step.")
    )

    replay = Conversation::Rehearsal.replay!(release_case(decisions: []), result: @result, model: @model)
    first, second = replay.transcript.calls

    assert_nil first.approval
    assert_match "migrate", first.result
    assert_equal Conversation::BenchCase::NOT_RECORDED, second.result
    assert_equal 1, replay.transcript.not_recorded
    assert_equal [ second.name ], replay.chat.tool_calls.where(failed: true).pluck(:name)
  end

  test "reading a connected system owes the answer a check before it goes out, as it does live" do
    script(
      call("northflank_api_request", "method" => "GET", "path" => "/v1/projects/web/workflows/release/runs"),
      reply("The migration is broken."),
      reply("Run 412 failed at the migrate step.")
    )

    replay = Conversation::Rehearsal.replay!(release_case(decisions: []), result: @result, model: @model)

    assert_includes replay.chat.messages.where(nudge: true, role: Chat::Message::ROLE_USER).map(&:content), FirefightAi::Responder::CHECK
    assert_equal [ "Run 412 failed at the migrate step." ], replay.transcript.replies
  end

  test "a chat that only reads Firefight's own records owes no check" do
    script(call("search_runbooks", "query" => "release"), reply("There is a release runbook."))

    replay = Conversation::Rehearsal.replay!(release_case(decisions: []), result: @result, model: @model)

    refute replay.chat.messages.exists?(nudge: true)
  end

  private

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
