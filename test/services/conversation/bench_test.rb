require "test_helper"

class Conversation::BenchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    RubyLLM.config.stubs(:openai_api_key).returns("sk-test")
    FirefightAi.stubs(:deployment_model_for).with(AiPurpose::INVESTIGATION).returns(FirefightAi::ModelChoice.new(model: "gpt-4o"))
  end

  test "a run queues every scenario in the bench's own workspace, on the deployment's model, and a second run finds the same workspace" do
    run = nil
    assert_enqueued_jobs Conversation::BenchCase.scenarios.size, only: HalonBenchCaseJob do
      run = Conversation::Bench.start!(trigger: Conversation::BenchRun::TRIGGER_OPERATOR, by: users(:alice))
    end

    workspace = run.results.first.workspace
    assert_equal Conversation::Bench::WORKSPACE_NAME, workspace.name
    assert_empty workspace.workspace_memberships
    assert_equal Conversation::BenchCase.scenarios.map(&:key).sort, run.results.pluck(:scenario).sort
    assert_equal [ "gpt-4o", users(:alice) ], [ run.model, run.started_by ]
    assert_equal FirefightAi::Responder.new(workspace, inferable: nil, model: FirefightAi::ModelChoice.new(model: "gpt-4o")).prompt_version, run.prompt_version
    assert_equal [ workspace.id ], Conversation::Bench.start!(trigger: Conversation::BenchRun::TRIGGER_OPERATOR).results.distinct.pluck(:workspace_id)
  end

  test "a scenario is replayed, judged and scored once, and the run finishes with it" do
    result = one_scenario_run
    script(reply("Run 412 failed at its migrate step, see https://example.test/runs/412."))
    judged(outcome: FirefightAi::Schemas::ReplayVerdict::REACHED, moved_forward: FirefightAi::Schemas::ReplayVerdict::PARTLY)

    Conversation::Bench.run_case!(result)
    result.reload

    assert_equal Conversation::BenchResult::STATUS_SCORED, result.status
    assert_equal [ 1.0, 0.5, 1.0, 1.0 ], [ result.right, result.moved_forward, result.asked_when_needed, result.cost ]
    assert_equal 0.875, result.total
    assert_equal "Run 412 failed at its migrate step, see https://example.test/runs/412.", result.answer
    assert_equal "It found the failed step.", result.reason
    assert result.bench_run.reload.status == Conversation::BenchRun::STATUS_FINISHED

    Conversation::Bench.expects(:score).never
    Conversation::Bench.run_case!(result)
  end

  test "from the terminal every scenario runs here and now, a few at a time, and each is reported as it settles" do
    one_scenario_run
    script(reply("Run 412 failed at its migrate step, see https://example.test/runs/412."))
    judged(outcome: FirefightAi::Schemas::ReplayVerdict::REACHED, moved_forward: FirefightAi::Schemas::ReplayVerdict::YES)
    reported = []

    run = Conversation::Bench.run!(trigger: Conversation::BenchRun::TRIGGER_CI, label: "abc123") { |result| reported << result.scenario }

    assert_equal [ "release" ], reported
    assert_equal [ Conversation::BenchRun::STATUS_FINISHED, Conversation::BenchRun::TRIGGER_CI, "abc123" ], [ run.status, run.trigger, run.label ]
    assert_equal 1.0, run.results.find_by!(scenario: "release").total
  end

  test "picking scenarios by a name that does not exist is refused before anything runs" do
    error = assert_raises(Conversation::BenchCase::Invalid) { Conversation::Bench.run!(trigger: Conversation::BenchRun::TRIGGER_TERMINAL, keys: [ "nope" ]) }

    assert_equal "No scenario is called nope.", error.message
    refute Conversation::BenchRun.exists?
  end

  test "a replay that raises could not finish, which says nothing either way" do
    result = one_scenario_run
    Conversation::Rehearsal.stubs(:replay!).raises(Timeout::Error)

    Conversation::Bench.run_case!(result)

    assert_equal Conversation::BenchResult::STATUS_ERRORED, result.reload.status
    assert_equal "The replay could not finish (Timeout::Error).", result.reason
    assert_nil result.total
  end

  test "a scenario whose worker was lost is settled by the hourly check, so its run can finish" do
    result = one_scenario_run
    result.update_columns(started_at: 3.hours.ago)

    HalonBenchWatchJob.perform_now

    assert_equal [ Conversation::BenchResult::STATUS_ERRORED, Conversation::Bench::LOST ], [ result.reload.status, result.reason ]
    assert_equal Conversation::BenchRun::STATUS_FINISHED, result.bench_run.reload.status
  end

  test "a job that comes back after its worker stopped mid replay settles the scenario rather than paying for it twice" do
    result = one_scenario_run
    job = HalonBenchCaseJob.new(result.id)
    assert result.claim!
    Conversation::Bench.stubs(:run_case!).raises(Interrupt)
    assert_raises(Interrupt) { job.perform_now }
    Conversation::Bench.unstub(:run_case!)

    Conversation::Rehearsal.expects(:replay!).never
    job.perform_now

    assert_equal [ Conversation::BenchResult::STATUS_ERRORED, Conversation::Bench::LOST ], [ result.reload.status, result.reason ]
  end

  test "a real chat is replayed in its own workspace from its record, with its right outcome left unscored" do
    conversation = chat_with_one_lookup
    script(call("get_incident", "incident" => "INC-001"), reply("INC-001 is resolved."))
    judged(outcome: FirefightAi::Schemas::ReplayVerdict::REACHED, moved_forward: FirefightAi::Schemas::ReplayVerdict::YES)

    run = Conversation::Bench.replay_chat!(conversation, trigger: Conversation::BenchRun::TRIGGER_TERMINAL)
    result = run.results.sole

    assert_equal [ Conversation::BenchRun::KIND_CHAT, conversation.workspace ], [ run.kind, result.workspace ]
    assert_equal Conversation::BenchResult::STATUS_SCORED, result.status
    assert_nil result.right
    assert_equal "INC-001 is resolved.", result.answer
    assert_equal 0, result.not_recorded
    assert_equal "Incident INC-001 is resolved.", result.chat.tool_calls.sole.result.content
  end

  private

  def one_scenario_run
    bench_case = Conversation::BenchCase.from_hash({
      "title" => "Release", "context" => "You are acting for Sam.", "turns" => [ "how did the release go?" ],
      "tools" => [ { "name" => "read_run", "description" => "Reads a run", "reads" => true } ],
      "answers" => [ { "tool" => "read_run", "result" => "Run 412 failed at migrate. https://example.test/runs/412" } ],
      "expect" => { "outcome" => "Run 412 failed at migrate", "next_step" => "Offer a retry", "evidence" => [ "runs/412" ] }
    }, key: "release")
    Conversation::BenchCase.stubs(:scenarios).returns([ bench_case ])
    Conversation::Bench.start!(trigger: Conversation::BenchRun::TRIGGER_TERMINAL).results.sole
  end

  def chat_with_one_lookup
    workspace = workspaces(:slack_workspace_one)
    conversation = Conversation.start_personal!(workspace: workspace, member: workspace_memberships(:alice_workspace_one))
    chat = Chat.open!(owner: conversation, workspace: workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o"))
    chat.messages.create!(role: Chat::Message::ROLE_SYSTEM, content: "The prompt.\nYou are acting for Alice, whose role in this workspace is member.")
    chat.messages.create!(role: Chat::Message::ROLE_USER, content: "is INC-001 still open?")
    asked = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    asked.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "get_incident", arguments: { "incident" => "INC-001" })
    answered = chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: "Incident INC-001 is resolved.")
    asked.ruby_llm_tool_calls.sole.update!(result: answered)
    chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "It is resolved.")
    conversation
  end

  def judged(outcome:, moved_forward:)
    FirefightAi::ReplayJudge.any_instance.stubs(:judge).returns(
      FirefightAi::ReplayJudge::Verdict.new(outcome: outcome, moved_forward: moved_forward, questions: 0, unneeded_questions: 0, reason: "It found the failed step.")
    )
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
