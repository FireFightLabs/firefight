require "test_helper"

class FirefightAi::ContractsTest < ActiveSupport::TestCase
  class FakePlanner
    include FirefightAi::Contracts::Planner

    def plan(request)
      [ FirefightAi::Contracts::Planner::Theory.new(
        assertion: "The deploy broke it", specialist: "code", first_question: "What shipped?",
        max_turns: request.max_turns
      ) ]
    end
  end

  class SilentPlanner
    include FirefightAi::Contracts::Planner
  end

  teardown { FirefightAi::Contracts.reset! }

  test "a contract with no implementation says so instead of guessing" do
    error = assert_raises(FirefightAi::Contracts::NoImplementation) do
      FirefightAi::Contracts.resolve(FirefightAi::Contracts::PLANNER)
    end

    assert_match "planner", error.message
  end

  test "an implementation is swapped by registration" do
    FirefightAi::Contracts.use(FirefightAi::Contracts::PLANNER, FakePlanner)

    assert FirefightAi::Contracts.registered?(FirefightAi::Contracts::PLANNER)
    assert_equal FakePlanner, FirefightAi::Contracts.resolve(FirefightAi::Contracts::PLANNER)
  end

  test "an implementation named as a string resolves to the class" do
    FirefightAi::Contracts.use(FirefightAi::Contracts::PLANNER, FakePlanner.name)

    assert_equal FakePlanner, FirefightAi::Contracts.resolve(FirefightAi::Contracts::PLANNER)
  end

  test "a contract nobody declared is refused" do
    assert_raises(ArgumentError) { FirefightAi::Contracts.use(:telepathy, FakePlanner) }
  end

  test "the planner shape carries the budget through to every theory" do
    request = FirefightAi::Contracts::Planner::Request.new(
      seed_pack: { incident: "INC-001" }, max_turns: 8, max_tokens: 1_000
    )

    theories = FakePlanner.new.plan(request)

    assert_equal 1, theories.length
    assert_equal 8, theories.first.max_turns
    assert_equal "code", theories.first.specialist
  end

  test "an implementation that skips the method fails loudly" do
    request = FirefightAi::Contracts::Planner::Request.new(seed_pack: {}, max_turns: 1, max_tokens: 1)

    assert_raises(NotImplementedError) { SilentPlanner.new.plan(request) }
  end

  test "every contract declares its own shapes" do
    assert FirefightAi::Contracts::BranchRunner::Outcome.members.include?(:evidence)
    assert FirefightAi::Contracts::Specialist::Answer.members.include?(:evidence)
    assert FirefightAi::Contracts::ConfidenceScorer::Score.members.include?(:factors)
    assert FirefightAi::Contracts::Matcher::Signature.members.include?(:issue_codes)
  end
end
