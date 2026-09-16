require "test_helper"

class Investigation::RunnerTest < ActiveSupport::TestCase
  # Stands in for the engine, so the run's bookkeeping is tested without calling a model.
  class FakeInvestigator
    attr_reader :calls

    def initialize(investigation, outcome:, turns: [], conclude: false)
      @investigation = investigation
      @outcome = outcome
      @turns = turns
      @conclude = conclude
      @calls = []
    end

    def run(**arguments)
      @calls << arguments
      @turns.each { |turn| yield turn }
      @investigation.conclude!(summary: "The 14:02 deploy raised the pool size") if @conclude
      @outcome
    end

    def ai_model = FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic")
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      triggered_by: workspace_memberships(:alice_workspace_one), max_turns: 10, max_spend_cents: 400
    )
    @investigation.claim!
  end

  test "an answered run succeeds and keeps the chat that produced it" do
    investigator = fake(outcome: :answered, conclude: true)

    result = Investigation::Runner.new(@investigation).run

    assert_equal Investigation::STATUS_SUCCEEDED, result.status
    assert_nil result.error_summary
    assert_match "claude-sonnet-4-5", @investigation.reload.chat.model_id
    assert_equal @workspace, @investigation.chat.workspace
    assert_equal @investigation.seed_pack, investigator.calls.sole[:seed_pack]
  end

  test "a run that never answers fails and says why" do
    fake(outcome: :out_of_budget)

    result = Investigation::Runner.new(@investigation).run

    assert_equal Investigation::STATUS_FAILED, result.status
    assert_equal "Budget spent before it could answer", result.error_summary
  end

  test "each turn is written down as it happens" do
    fake(outcome: :answered, conclude: true, turns: [ turn(1, 3), turn(2, 9) ])

    Investigation::Runner.new(@investigation).run

    @investigation.reload
    assert_equal 2, @investigation.turns_used
    assert_equal 9, @investigation.spent_cents
  end

  test "the run stops when another worker has taken it over" do
    fake(outcome: :answered, turns: [ turn(1, 3) ])
    Investigation.any_instance.stubs(:record_turn!).returns(false)

    assert_raises(Investigation::Runner::LeaseLost) { Investigation::Runner.new(@investigation).run }
  end

  test "the engine is given what the run has already spent, so a resumed run cannot spend it twice" do
    @investigation.update!(turns_used: 4, spent_cents: 120)
    investigator = fake(outcome: :answered, conclude: true)

    Investigation::Runner.new(@investigation).run

    budget = investigator.calls.sole[:budget]
    assert_equal 4, budget.turns_used
    assert_equal 120, budget.spent_cents
    assert_equal 400, budget.max_spend_cents
    assert_equal 10, budget.max_turns
  end

  test "an empty reply left by a killed worker is cleared before the run resumes" do
    chat = @investigation.create_chat!(workspace: @workspace, model: "claude-sonnet-4-5", provider: :anthropic)
    chat.add_message(role: :user, content: "Investigate")
    interrupted = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    fake(outcome: :answered, conclude: true)

    Investigation::Runner.new(@investigation).run

    assert_not Chat::Message.exists?(interrupted.id)
  end

  private

  def turn(turns_used, spent_cents)
    FirefightAi::AgentLoop::Turn.new(turns_used: turns_used, spent_cents: spent_cents)
  end

  def fake(outcome:, turns: [], conclude: false)
    investigator = FakeInvestigator.new(
      @investigation,
      outcome: FirefightAi::AgentLoop::Outcome.new(status: outcome, turns_used: turns.size, spent_cents: 0),
      turns: turns, conclude: conclude
    )
    FirefightAi::Investigator.stubs(:new).returns(investigator)
    investigator
  end
end
