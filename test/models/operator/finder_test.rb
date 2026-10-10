require "test_helper"

class Operator::FinderTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @run = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 20, max_spend_cents: 400,
      status: Investigation::STATUS_SUCCEEDED, completed_at: Time.current
    )
  end

  test "a whole id or its start finds the record" do
    assert_equal [ [ Operator::Finder::KIND_RUN, @run.id ] ], found(@run.id)
    assert_includes found(@run.id.first(8)), [ Operator::Finder::KIND_RUN, @run.id ]
  end

  test "an incident number is looked up in every workspace, whatever its case" do
    matches = Operator::Finder.new(@incident.identifier.downcase).matches

    assert matches.all? { |match| match.kind == Operator::Finder::KIND_INCIDENT }
    assert_includes matches.map(&:id), @incident.id
  end

  test "a trace row's id, as its address shows it, opens the run at that row" do
    inference = Inference.create!(workspace: @workspace, feature: FirefightAi::Investigator::FEATURE, provider: "anthropic", model: "claude",
                                  status: Inference::STATUS_SUCCESS, inferable: @run)

    match = Operator::Finder.new("#{Operator::Trace::KIND_MODEL}-#{inference.id}").matches.sole

    assert_equal @run.id, match.id
    assert_equal "#{Operator::Trace::KIND_MODEL}-#{inference.id}", match.span
    assert_match "span=#{Operator::Trace::KIND_MODEL}-#{inference.id}", Operator::FindMatchSerializer.path_for(match)
  end

  test "a ledger entry leads back to the run whose tool call it was" do
    invocation = Ability::Invocation.create!(
      workspace: @workspace, principal: SystemAgent.investigator, principal_label: "Firefight Investigator", action_key: "github.show_commit",
      idempotency_key: SecureRandom.uuid, decision: Ability::Invocation::DECISION_ALLOW, source: AbilityGateway::SOURCE_INVESTIGATION
    )
    @run.steps.create!(position: 1, action_key: "github.show_commit", status: Investigation::Step::STATUS_SUCCEEDED, invocation: invocation)

    assert_includes found(invocation.id), [ Operator::Finder::KIND_RUN, @run.id ]
  end

  test "a bench run, or anything in a scenario's replay, leads to the run, and a real chat's replay to the chat it replayed" do
    run = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_SCENARIOS, trigger: Conversation::BenchRun::TRIGGER_CI, prompt_version: "v1", model: "gpt-4o")
    result = run.results.create!(workspace: @workspace, scenario: "release", title: "Release")
    chat = Chat.open!(owner: result, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o"))
    message = chat.messages.create!(role: Chat::Message::ROLE_USER, content: "release to production")

    assert_equal [ [ Operator::Finder::KIND_BENCH, run.id ] ], found(run.id)
    assert_equal [ [ Operator::Finder::KIND_BENCH, run.id ] ], found(chat.id)
    assert_equal [ [ Operator::Finder::KIND_BENCH, run.id ] ], found(message.id)
    assert_equal "/operator/halon/bench/#{run.id}", Operator::FindMatchSerializer.path_for(Operator::Finder.new(run.id).matches.sole)

    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    replay = Conversation::BenchRun.create!(kind: Conversation::BenchRun::KIND_CHAT, trigger: Conversation::BenchRun::TRIGGER_TERMINAL, prompt_version: "v1", model: "gpt-4o")
    replayed = replay.results.create!(workspace: @workspace, replay_of: conversation, scenario: "chat-#{conversation.id}", title: "Chat")
    replay_chat = Chat.open!(owner: replayed, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o"))

    assert_equal [ [ Operator::Finder::KIND_CHAT, conversation.id ] ], found(replay_chat.id)
    assert_empty found(replay.id)
  end

  test "too short a start, or anything that is not an id, finds nothing" do
    assert_empty found(@run.id.first(4))
    assert_empty found("drop table incidents")
    assert_empty found("")
  end

  private

  def found(query) = Operator::Finder.new(query).matches.map { |match| [ match.kind, match.id ] }
end
