require "test_helper"

class Workflow::Run::ActivityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release", created_by: @alice)
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "kind" => "manual", "inputs" => [] }, steps: [ { "id" => "follow", "name" => "follow", "kind" => "delay", "config" => { "minutes" => 5 } } ])
    perform_enqueued_jobs { @run = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true) }
    @run.reload
    @row = @run.steps.sole
    @row.update!(started_at: 10.minutes.ago)
  end

  def activity = Workflow::Run.find(@run.id).activity(describe_tool: ->(name, arguments) { Chat::Tools.step(name, arguments, workspace: @workspace) })

  def call!(at:, action_key: "integrations.github.workflow_runs", source: Chat::Watch::SOURCE, completed: true, outcome: Ability::Invocation::OUTCOME_SUCCESS)
    Ability::Invocation.create!(workspace: @workspace, principal: @alice, principal_label: "Alice", action_key: action_key, decision: Ability::Invocation::DECISION_ALLOW,
                                outcome: (outcome if completed), duration_ms: (300 if completed), source: source, idempotency_key: SecureRandom.uuid,
                                created_at: at, completed_at: (at if completed), **@row.ledger_context)
  end

  def watch!(**attributes)
    chat = Chat.open!(owner: @row, workspace: @workspace, model_choice: FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace))
    Chat::Watch.create!(chat: chat, workspace: @workspace, asker: @alice, title: "Release", expires_at: 50.minutes.from_now, limit_basis: Chat::Watch::BASIS_DEFAULT,
                        **attributes)
  end

  test "a watch's reads of the same thing in a row read as one line, with what it saw and said in between and where it stands now" do
    watch = watch!(checked_at: 20.seconds.ago, reads_total: 3)
    followed = Chat::Watch::Step.create!(watch: watch, position: 1, label: "Web rollout", capability: Integrations::Capabilities::STATUS, status: Chat::Watch::Step::STATUS_RUNNING,
                                         summary: "build running, 2 of 5 done", last_state: "deploying", read_at: 20.seconds.ago,
                                         readings: [ { Chat::Watch::Step::READING_AT => 2.minutes.ago.utc.iso8601, Chat::Watch::Step::READING_TEXT => "deploying" } ])
    call!(at: 3.minutes.ago)
    call!(at: 150.seconds.ago)
    Chat::Watch::Update.create!(watch: watch, kind: Chat::Watch::Update::KIND_STARTED, text: "Web rollout started.", created_at: 140.seconds.ago)
    call!(at: 60.seconds.ago)

    log = activity.log_for(@row)

    assert_equal [ "Started.", "Read integrations.github.workflow_runs", "Web rollout started.", "Web rollout: saw something new", "Read integrations.github.workflow_runs" ],
                 log.map { |entry| entry[:text] }
    assert_equal [ 2, "Allowed, ended in success after 300 ms." ], log.second.values_at(:count, :detail)
    assert_equal "deploying", log.fourth[:detail]
    assert_equal "Web rollout: build running, 2 of 5 done", activity.now_for(@row)

    shown = activity.watching_for(@row)
    assert shown[:active]
    assert_equal [ "Web rollout", "build running, 2 of 5 done", "deploying" ], shown[:steps].sole.values_at(:label, :line, :lastSeen)
    assert_in_delta 40.seconds.from_now, Time.zone.parse(shown[:nextCheckAt]), 2
    assert_equal followed.id, shown[:steps].sole[:id]
  end

  test "a call still waiting for its answer is what the step is doing now" do
    call!(at: 5.seconds.ago, action_key: "integrations.github.run_workflow", source: AbilityGateway::SOURCE_WORKFLOW, completed: false)

    assert_equal "Calling integrations.github.run_workflow.", activity.now_for(@row)
    assert_equal [ "Called integrations.github.run_workflow, waiting for its answer", "waiting" ], activity.log_for(@row).last.values_at(:text, :tone)
  end

  test "each tool Halon calls for the step is in its log as it goes, and the one it waits on is what it does now" do
    chat = Chat.open!(owner: @row, workspace: @workspace, model_choice: FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace))
    asked = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    done = asked.ruby_llm_tool_calls.create!(tool_call_id: "c_1", name: FirefightTools::SEARCH_INCIDENTS, arguments: { "query" => "checkout" })
    done.update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: "INC-1 Checkout failing"))
    asked.ruby_llm_tool_calls.create!(tool_call_id: "c_2", name: FirefightTools::SEARCH_INCIDENTS, arguments: { "query" => "payments" })

    halon = activity.log_for(@row).select { |entry| entry[:text].start_with?("Halon: ") }

    assert_equal [ "good", "waiting" ], halon.map { |entry| entry[:tone] }
    assert_includes halon.first[:detail], "INC-1 Checkout failing"
    assert_match(/\AHalon: .+\.\z/, activity.now_for(@row))
  end

  test "a step that ended says so last, and is doing nothing now" do
    @row.update!(status: DefinedWorkflow::STEP_SUCCEEDED, route: "timed_out", finished_at: Time.current)

    assert_equal "Done. It took the timed out way.", activity.log_for(@row).last[:text]
    assert_nil activity.now_for(@row)
    assert_nil activity.watching_for(@row)
  end

  test "a step that failed on a route with nothing after it says which way it went and why" do
    @row.update!(status: DefinedWorkflow::STEP_FAILED, route: "timed_out", error: "Watch the rollout timed out after 1 hour.", finished_at: Time.current)

    assert_equal [ "Failed. It took the timed out way.", "Watch the rollout timed out after 1 hour." ], activity.log_for(@row).last.values_at(:text, :detail)
  end

  test "a watch kept by a workflow step ledgers each read under the run and the step" do
    watch = watch!
    reader = Conversation::Watches::Reader.new(workspace: @workspace, principal: @alice, conversation: watch.conversation)

    assert_equal({ workflow_run_id: @run.id, workflow_step_key: "follow" }, watch.conversation.ledger_context)
    Chat::ToolCall.expects(:run!).with { |**given| given[:context].slice(:source, :workflow_run_id, :workflow_step_key) == { source: Chat::Watch::SOURCE, workflow_run_id: @run.id, workflow_step_key: "follow" } }.returns("ok")
    tool = stub(action_key: "integrations.github.workflow_runs", integration: stub(name: "GitHub"), name: "workflow_runs")
    reader.send(:authorized, tool, {}, {}) { "ok" }
  end
end
