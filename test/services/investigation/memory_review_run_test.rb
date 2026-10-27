require "test_helper"

class Investigation::MemoryReviewRunTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @memory = Chat::Memory.create!(workspace: @workspace, text: "web deploys from main", state: Chat::Memory::STATE_UNCONFIRMED)
    @review = Chat::MemoryReview.open!(@workspace)
    @review.picked!([ @memory ])
    @run = @workspace.investigations.create!(subject: @review, trigger_source: Investigation::TRIGGER_MEMORY_REVIEW, max_turns: 10, max_spend_cents: 400)
    @run.steps.create!(position: 1, tool_name: "get_service", label: "Settings of web", action_key: "northflank.get_service",
                       status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)
  end

  def settle(**arguments)
    Investigation::Tools::SettleMemory.new(@run).call("memory" => @memory.id, "verdict" => "right", "evidence" => "The deploy settings of web name main.",
                                                      "steps" => [ 1 ], **arguments)
  end

  test "a memory check is handed settle_memory and finish_memory_check, and no memory tool that learns or disputes" do
    assert_equal %w[settle_memory finish_memory_check], Investigation::Tools.own_tools(@run).map(&:name)
    assert_equal [ Chat::Tools::SearchHandbook ], Investigation::Tools.memory_tools(@run).map(&:class)
  end

  test "its facts hold tonight's memories in the encrypted notes, never in the plain facts, and hand it nothing as a hunch" do
    @run.build_seed_pack!

    assert_not_includes @run.seed_pack.to_json, "web deploys from main"
    checked = @run.starting_facts[Investigation::Seeding::KEY_TO_CHECK].sole
    assert_equal [ @memory.id, "web deploys from main", "the whole workspace", "nobody yet" ], checked.values_at("id", "fact", "about", "stands_behind")
    assert_empty @run.starting_facts[Investigation::Seeding::KEY_MEMORIES]
    assert_equal 0, @memory.reload.use_count
  end

  test "right needs a step tonight behind it, and settles through the gateway as the investigator, with ids only in the ledger" do
    assert_match "cites step 9", settle("steps" => [ 9 ])
    assert_match "is not one of tonight's", settle("memory" => Chat::Memory.create!(workspace: @workspace, text: "Backups run nightly", state: Chat::Memory::STATE_UNCONFIRMED).id)
    assert_equal Chat::Memory::STATE_UNCONFIRMED, @memory.reload.state

    assert_equal "Confirmed by your check.", settle

    assert_equal Chat::Memory::STANDING_HALON, @memory.reload.standing
    entry = @workspace.ability_invocations.find_by!(action_key: "memory.update", principal: SystemAgent.investigator)
    assert_equal({ "memory" => @memory.id, "verdict" => "right" }, entry.params)
    assert_equal AbilityGateway::SOURCE_INVESTIGATION, entry.source
  end

  test "a wrong verdict on a memory a person confirmed disputes it for them and queues one direct message to them" do
    @memory.confirm!(by: workspace_memberships(:alice_workspace_one))

    assert_enqueued_with(job: MemoryChallengeJob, args: [ @memory.id ]) do
      assert_match "they are told", settle("verdict" => "wrong", "evidence" => "The deploy settings of web name release.")
    end
    assert_equal Chat::Memory::STATE_DISPUTED, @memory.reload.state
  end

  test "unsure needs no step, and an admin who revokes the investigator's memory grant stops every verdict" do
    assert_equal "Kept as it is, marked as not checked yet.", settle("verdict" => "unsure", "steps" => nil, "evidence" => "Nothing connected reads deploys.")

    other = Chat::Memory.create!(workspace: @workspace, text: "Backups run nightly", state: Chat::Memory::STATE_UNCONFIRMED)
    @review.picked!([ @memory, other ])
    @workspace.ability_grants.where(principal: SystemAgent.investigator, action: Ability::Action.where(key: "memory.update")).destroy_all

    assert_equal "Not allowed: this agent has no grant for memory.update in this workspace.", settle("memory" => other.id)
    assert_equal Chat::Memory::STATE_UNCONFIRMED, other.reload.state
  end

  test "finish writes the run's answer from what was settled, and the end marks what was never settled as tried tonight" do
    other = Chat::Memory.create!(workspace: @workspace, text: "Backups run nightly", state: Chat::Memory::STATE_UNCONFIRMED)
    @review.picked!([ @memory, other ])
    settle

    Investigation::Tools::FinishMemoryCheck.new(@run).call
    Investigation::Delivery.for(@run).answered!(@run.reload.finding)

    assert_equal "Checked 1 of 2 memories against production. 1 not reached, kept as not checked.", @run.finding.summary
    assert_equal Chat::Memory::VERDICT_UNSURE, other.reload.check_outcome
    assert_not @run.finding.search_embeddable?
  end

  # Stands in for the engine, so the run's bookkeeping is tested without calling a model.
  class FakeChecker
    attr_reader :tool_names

    def initialize(run) = @run = run

    def run(**arguments)
      @tool_names = arguments[:tools].map(&:name)
      FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET, turns_used: 1, spent_micros: 0)
    end

    def ai_model = FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic")
  end

  test "a memory check runs on its own prompts, says nothing anywhere, and one stopped early keeps what it never reached" do
    @run.claim!
    checker = FakeChecker.new(@run)
    FirefightAi::MemoryChecker.expects(:new).with(@workspace, inferable: @run, model: anything).returns(checker)
    FirefightAi::Investigator.expects(:new).never
    Workflow::Trigger::Events.expects(:fire!).never

    result = Investigation::Runner.new(@run).run
    @run.finish!(status: result.status, error_summary: result.error_summary)

    assert_includes checker.tool_names, "settle_memory"
    assert_not_includes checker.tool_names, "remember"
    assert_equal [ Chat::Memory::VERDICT_UNSURE, Chat::Memory::STATE_UNCONFIRMED ], @memory.reload.values_at(:check_outcome, :state)
    assert @review.reload.finished_at
  end

  test "Halon's performance leaves the nightly memory check out" do
    @run.conclude!(summary: "Checked 1 of 1 memory against production.")
    @run.finish!(status: Investigation::STATUS_SUCCEEDED)

    performance = Investigation::Performance.new(@workspace)
    assert_not_includes performance.send(:runs), @run
    assert_not_includes Investigation::WORKFLOW_TRIGGER_SOURCES, Investigation::TRIGGER_MEMORY_REVIEW
  end
end
