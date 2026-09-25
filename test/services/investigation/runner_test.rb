require "test_helper"

class Investigation::RunnerTest < ActiveSupport::TestCase
  # Stands in for the engine, so the run's bookkeeping is tested without calling a model.
  class FakeInvestigator
    attr_reader :calls

    def initialize(investigation, outcome:, turns: [], conclude: false, take: false)
      @take = take
      @investigation = investigation
      @outcome = outcome
      @turns = turns
      @conclude = conclude
      @calls = []
    end

    def run(**arguments)
      @calls << arguments
      @turns.each { |turn| yield turn }
      arguments[:take_messages].call if @take
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
    # What a run says in Slack has its own test. Here it only has to not reach the network.
    Investigation::Delivery.any_instance.stubs(:start!)
    Investigation::Delivery.any_instance.stubs(:step)
    @answered = Investigation::Delivery.any_instance.stubs(:answered!)
    @stopped = Investigation::Delivery.any_instance.stubs(:stopped!)
  end

  test "a rehearsal says nothing anywhere, and runs on the model it was told to" do
    rehearsal = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true,
      model_override: "gpt-5-mini", provider_override: "openai", max_turns: 10, max_spend_cents: 400
    )
    rehearsal.claim!
    Investigation::Delivery.expects(:new).never
    investigator = FakeInvestigator.new(
      rehearsal, outcome: FirefightAi::AgentLoop::Outcome.new(status: :answered, turns_used: 0, spent_micros: 0), conclude: true
    )
    FirefightAi::Investigator.expects(:new).with(
      @workspace, inferable: rehearsal, member: nil, model: FirefightAi::ModelChoice.new(model: "gpt-5-mini", provider: "openai")
    ).returns(investigator)

    assert_equal Investigation::STATUS_SUCCEEDED, Investigation::Runner.new(rehearsal).run.status
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
    Investigation::Delivery.any_instance.expects(:stopped!).with("Budget spent before it could answer")

    result = Investigation::Runner.new(@investigation).run

    assert_equal Investigation::STATUS_FAILED, result.status
    assert_equal "Budget spent before it could answer", result.error_summary
  end

  test "an answer is posted where the run started" do
    fake(outcome: :answered, conclude: true)
    Investigation::Delivery.any_instance.expects(:answered!).with { |finding| finding == @investigation.reload.finding }

    Investigation::Runner.new(@investigation).run
  end

  test "a run someone stopped ends as canceled and says so" do
    fake(outcome: :canceled)
    Investigation::Delivery.any_instance.expects(:stopped!).with(Investigation::STOPPED_BY_A_RESPONDER)

    result = Investigation::Runner.new(@investigation).run

    assert_equal Investigation::STATUS_CANCELED, result.status
  end

  test "a model call stopped mid answer ends the run rather than failing it" do
    fake(outcome: :answered)
    FakeInvestigator.any_instance.stubs(:run).raises(FirefightAi::Canceled, "cancelled")
    Investigation::Delivery.any_instance.expects(:stopped!)

    result = Investigation::Runner.new(@investigation).run

    assert_equal Investigation::STATUS_CANCELED, result.status
    assert_equal Investigation::STOPPED_BY_A_RESPONDER, result.error_summary
  end

  test "each turn is written down as it happens" do
    fake(outcome: :answered, conclude: true, turns: [ turn(1, 3), turn(2, 9) ])

    Investigation::Runner.new(@investigation).run

    @investigation.reload
    assert_equal 2, @investigation.turns_used
    assert_equal 9, @investigation.spent_micros
  end

  test "the run stops when another worker has taken it over" do
    fake(outcome: :answered, turns: [ turn(1, 3) ])
    Investigation.any_instance.stubs(:record_turn!).returns(false)

    assert_raises(Investigation::Runner::LeaseLost) { Investigation::Runner.new(@investigation).run }
  end

  test "the engine is given what the run has already spent, so a resumed run cannot spend it twice" do
    @investigation.update!(turns_used: 4, spent_micros: 1_200_000)
    investigator = fake(outcome: :answered, conclude: true)

    Investigation::Runner.new(@investigation).run

    budget = investigator.calls.sole[:budget]
    assert_equal 4, budget.turns_used
    assert_equal 1_200_000, budget.spent_micros
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

  test "a resumed run is handed back the tools it had found" do
    action = Ability::Action.system!(
      Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)
    )
    Ability::Grant.create!(workspace: @workspace, principal: @investigation.acting_principal, action: action)
    chat = @investigation.create_chat!(workspace: @workspace, model: "claude-sonnet-4-5", provider: :anthropic)
    chat.remember_found_tools!([ Mcp::Tools::SEARCH_INCIDENTS ])
    investigator = fake(outcome: :answered, conclude: true)

    Investigation::Runner.new(@investigation).run

    assert_includes investigator.calls.sole[:tools].map(&:name), Mcp::Tools::SEARCH_INCIDENTS
  end

  test "a responder's note joins the run at its next step, says who added it, and shows as a step" do
    bob = workspace_memberships(:bob_workspace_one)
    @investigation.add_note!("skip GitHub, look at 5xx on web", by: bob)
    fake(outcome: :answered, conclude: true, take: true)
    Investigation::Delivery.any_instance.expects(:step).with(
      key: "note-#{@investigation.notes.sole.id}", title: "Read what #{bob.display_name} added", status: FirefightAi::AgentLoop::STEP_DONE
    )

    Investigation::Runner.new(@investigation).run

    said = @investigation.chat.messages.where(role: Chat::Message::ROLE_USER).map(&:content)
    assert_includes said, "#{bob.display_name} added: skip GitHub, look at 5xx on web"
    assert @investigation.notes.sole.taken_at
  end

  private

  def turn(turns_used, spent_micros)
    FirefightAi::AgentLoop::Turn.new(turns_used: turns_used, spent_micros: spent_micros)
  end

  def fake(outcome:, turns: [], conclude: false, take: false)
    investigator = FakeInvestigator.new(
      @investigation,
      outcome: FirefightAi::AgentLoop::Outcome.new(status: outcome, turns_used: turns.size, spent_micros: 0),
      turns: turns, conclude: conclude, take: take
    )
    FirefightAi::Investigator.stubs(:new).returns(investigator)
    investigator
  end
end
