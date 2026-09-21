require "test_helper"

class Investigation::EvidenceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    @deploys = step!("recent_deployments", "Recent deployments checkout")
    @commit = step!("commit_lookup", "Commit lookup abc123")
  end

  test "steps are numbered within their run, in the order they happened" do
    assert_equal [ 1, 2 ], @investigation.steps.map(&:position)
  end

  test "evidence is a claim and the steps it rests on, never a sentence on its own" do
    finding = @investigation.conclude!(
      summary: "The 14:02 deploy raised the pool size",
      evidence: [ { claim: "A deploy went out at 14:02", steps: [ 1 ] }, { claim: "It raised the pool size", steps: [ 1, 2 ] } ]
    )

    first, second = finding.evidence_items.to_a
    assert_equal "A deploy went out at 14:02", first.claim
    assert_equal [ @deploys ], first.citations.map(&:source)
    assert_equal [ @deploys, @commit ], second.citations.map(&:source)
  end

  test "a claim that cites nothing is refused, so the agent has to say what it rests on" do
    error = assert_raises(Investigation::Evidence::Refused) do
      @investigation.conclude!(summary: "It was the deploy", evidence: [ { claim: "A deploy went out", steps: [] } ])
    end

    assert_match "cites no step", error.message
    assert_nil @investigation.reload.finding, "a refused conclusion leaves no answer behind"
  end

  test "a claim citing a step that never happened is refused, and told which steps exist" do
    error = assert_raises(Investigation::Evidence::Refused) do
      @investigation.conclude!(summary: "It was the deploy", evidence: [ { claim: "A deploy went out", steps: [ 9 ] } ])
    end

    assert_match "step 9", error.message
    assert_match "1 to 2", error.message
  end

  test "a claim citing a step that failed is refused, since a failed call showed nothing" do
    failed = step!("log_query", "Log query errors", status: Investigation::Step::STATUS_FAILED)

    error = assert_raises(Investigation::Evidence::Refused) do
      @investigation.conclude!(summary: "Errors spiked", evidence: [ { claim: "Errors spiked", steps: [ failed.position ] } ])
    end

    assert_match "failed", error.message
  end

  test "naming a cause needs evidence behind it" do
    @investigation.record_hypothesis!(assertion: "The 14:02 deploy did it")

    error = assert_raises(Investigation::Evidence::Refused) do
      @investigation.conclude!(summary: "It was the deploy", hypothesis_assertion: "The 14:02 deploy did it")
    end

    assert_match "evidence", error.message
  end

  test "concluding that nothing explains it needs no evidence" do
    finding = @investigation.conclude!(summary: "Nothing in what I could reach explains it", gaps: "production logs")

    assert_empty finding.evidence_items
  end

  test "a theory marked supported or ruled out says which steps showed it" do
    hypothesis = @investigation.record_hypothesis!(
      assertion: "The database was saturated", status: Investigation::Hypothesis::STATUS_REFUTED, steps: [ 2 ]
    )

    assert_equal [ @commit ], hypothesis.citations.map(&:source)
  end

  test "a theory cannot be settled without saying what settled it" do
    error = assert_raises(Investigation::Evidence::Refused) do
      @investigation.record_hypothesis!(assertion: "The database was saturated", status: Investigation::Hypothesis::STATUS_REFUTED)
    end

    assert_match "which steps", error.message
  end

  test "an open theory needs no steps yet" do
    assert @investigation.record_hypothesis!(assertion: "Maybe the cache").persisted?
  end

  test "settling a theory again replaces what it rested on rather than piling up" do
    @investigation.record_hypothesis!(assertion: "The deploy", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    hypothesis = @investigation.record_hypothesis!(assertion: "The deploy", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 2 ])

    assert_equal [ @commit ], hypothesis.citations.reload.map(&:source)
  end

  private

  def step!(tool_name, label, status: Investigation::Step::STATUS_SUCCEEDED)
    @investigation.steps.create!(
      position: @investigation.next_step_position, tool_name: tool_name, label: label,
      action_key: "github.#{tool_name}", status: status, started_at: Time.current
    )
  end
end
