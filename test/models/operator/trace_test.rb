require "test_helper"

class Operator::TraceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @started = 3.minutes.ago
    @run = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 20, max_spend_cents: 400,
      status: Investigation::STATUS_SUCCEEDED, started_at: @started, completed_at: 1.minute.ago, attempts: 1,
      thread_id: "1.2", answer_posted_at: 1.minute.ago, seed_pack: { "alerts" => [ { "title" => "cpu" } ], "gathered_at" => @started.iso8601 }
    )
  end

  test "a run's tool call carries the gateway's decision, and its output is read only when opened" do
    invocation = Ability::Invocation.create!(
      workspace: @workspace, principal: SystemAgent.investigator, principal_label: "Firefight Investigator", action_key: "postgresql.current_activity",
      idempotency_key: SecureRandom.uuid, decision: Ability::Invocation::DECISION_ALLOW, outcome: Ability::Invocation::OUTCOME_SUCCESS,
      duration_ms: 612, source: AbilityGateway::SOURCE_INVESTIGATION
    )
    step = @run.steps.create!(position: 1, tool_name: "postgresql_current_activity", action_key: "postgresql.current_activity",
                              status: Investigation::Step::STATUS_SUCCEEDED, invocation: invocation, started_at: @started + 5.seconds,
                              completed_at: @started + 6.seconds, raw_result: "state | connections\nactive | 96")

    trace = Operator::RunTrace.new(@run)
    span = trace.spans.find { |candidate| candidate.key == "tool-#{step.id}" }

    assert_match "allowed", span.detail
    assert_includes span.facts, [ "Ledger", invocation.id ]
    assert_includes span.facts, [ "As", "Firefight Investigator" ]
    assert span.body?
    assert_match "active | 96", trace.body_for(span.key)
  end

  test "a call with no ledger row says what it was, never that it was replayed when the run is not a replay" do
    read = @run.steps.create!(position: 1, tool_name: "get_incident", action_key: "incidents.read", status: Investigation::Step::STATUS_SUCCEEDED,
                              started_at: @started, completed_at: @started + 1.second)
    refused = @run.steps.create!(position: 2, tool_name: "github_changes_before", action_key: "github.changes_before",
                                 status: Investigation::Step::STATUS_FAILED, error_summary: "Denied", started_at: @started)

    spans = Operator::RunTrace.new(@run).spans.index_by(&:key)

    assert_match "allowed, own data", spans["tool-#{read.id}"].detail
    assert_includes spans["tool-#{read.id}"].facts, [ "Decision", "allowed, a read of Firefight's own data, which the gateway does not ledger" ]
    assert_equal Operator::IncidentProcess::TONE_BAD, spans["tool-#{refused.id}"].tone
    assert_match "denied", spans["tool-#{refused.id}"].detail
    assert_no_match "replayed", spans.values.map(&:detail).join
  end

  test "each model call sits on the clock where it ran, with its tokens and cost" do
    inference = Inference.create!(workspace: @workspace, feature: FirefightAi::Investigator::FEATURE, provider: "anthropic", model: "claude",
                                  status: Inference::STATUS_SUCCESS, inferable: @run, input_tokens: 400, cache_read_tokens: 18_000,
                                  output_tokens: 410, cost_micros: 60_000, latency_ms: 2000, prompt_template: FirefightAi::Investigator::FEATURE,
                                  prompt_version: "683e92b9f7ac")

    trace = Operator::RunTrace.new(@run)
    span = trace.spans.find { |candidate| candidate.key == "model-#{inference.id}" }

    assert_in_delta inference.created_at - 2.seconds, span.started_at, 0.01
    assert_equal "18.4k in, 18.0k cached · 410 out · $0.06", span.detail
    assert_equal "683e92b9f7ac", trace.prompt_version
  end

  test "a run that answered shows the answer and that it reached the thread, and one that did not post says so" do
    @run.conclude!(summary: "The 14:02 deploy did it")

    kinds = Operator::RunTrace.new(@run).spans.map(&:title)
    assert_includes kinds, "Answer recorded"
    assert_includes kinds, "Posted to the thread"

    @run.update_columns(answer_posted_at: nil)
    lost = Operator::RunTrace.new(@run.reload).spans.find { |span| span.key == "not-posted" }
    assert_equal Operator::IncidentProcess::TONE_BAD, lost.tone
  end

  test "a run that failed on our side says so with the recorded cause" do
    @run.update_columns(status: Investigation::STATUS_FAILED, error_summary: "Faraday::TimeoutError")

    stop = Operator::RunTrace.new(@run.reload).spans.find { |span| span.key == "stop" }

    assert_equal "Failed", stop.title
    assert_includes stop.facts, [ "Recorded cause", "Faraday::TimeoutError" ]
  end

  test "a chat's tool call lasts from when its result was saved until it was filled in, and the next model call starts after it" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    start = 2.minutes.ago
    chat.add_message(role: :user, content: "Which workspaces do we have?").update_columns(created_at: start, updated_at: start)
    asking = chat.add_message(role: :assistant, content: "")
    asking.update_columns(created_at: start + 1.second, updated_at: start + 3.seconds)
    result = chat.add_message(role: :tool, content: "2 rows")
    result.update_columns(created_at: start + 3.seconds, updated_at: start + 27.seconds)
    call = RubyLLM::ActiveRecord::ToolCall.create!(message: asking, tool_call_id: "call_1", name: "run_query", arguments: {}, result: result)
    reply = chat.add_message(role: :assistant, content: "Two.")
    reply.update_columns(created_at: start + 27.seconds, updated_at: start + 29.seconds)
    usage = RubyLLM::ActiveRecord::Usage.create!(chat: chat, message: reply, operation: "chat", provider: "anthropic", model: "claude",
                                                 status: "succeeded", input_tokens: 10, output_tokens: 2)
    usage.update_columns(created_at: start + 29.seconds, updated_at: start + 29.seconds)

    spans = Operator::ChatTrace.new(conversation.reload).spans.index_by(&:key)

    tool = spans["call-#{call.id}"]
    model = spans["model-#{usage.id}"]
    assert_in_delta 24, tool.ended_at - tool.started_at, 0.01
    assert_in_delta 2, model.ended_at - model.started_at, 0.01
  end

  test "a chat is drawn one turn at a time, each from what the person asked" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    chat.add_message(role: :system, content: "You are Halon.")
    chat.add_message(role: :user, content: "What changed today?")
    chat.add_message(role: :assistant, content: "Two deploys went out.")
    chat.add_message(role: :user, content: "Which one broke checkout?")
    chat.nudge!("Keep going.")
    chat.add_message(role: :assistant, content: "The 14:02 one.")

    trace = Operator::ChatTrace.new(conversation.reload)

    assert_equal 2, trace.turn_count
    assert_equal [ "Turn 1", "Turn 2" ], trace.groups.map(&:title)
    second = trace.groups.last.spans
    assert_equal "Which one broke checkout?", second.find { |span| span.kind == Operator::Trace::KIND_ASK }.detail
    assert_equal "The 14:02 one.", second.find { |span| span.kind == Operator::Trace::KIND_REPLY }.detail
  end
end
