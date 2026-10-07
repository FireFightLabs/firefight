require "test_helper"

class Slack::Messages::InvestigationRunTest < ActiveSupport::TestCase
  include FixPlanTestHelper
  setup do
    @incident = incidents(:active_critical_ws1)
    investigation = @incident.workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    investigation.steps.create!(
      position: 1, tool_name: "commit_lookup", label: "Commit lookup abc123", action_key: "github.commit_lookup",
      status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current
    )
    @finding = investigation.conclude!(
      summary: "The **14:02 deploy** raised the pool size",
      evidence: [ { claim: "The commit raised the pool size", steps: [ 1 ] } ], gaps: "production logs"
    )
  end

  test "a question with no incident is announced by its own words, escaped" do
    text = Slack::Messages::InvestigationRun.started(incident: nil, question: "is <checkout> slow", started_by: "Alice").sole.dig(:text, :text)

    assert_match "is &lt;checkout&gt; slow", text
  end

  test "an answer that says users are hurt now, with no incident, offers to declare one" do
    run = @incident.workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
    finding = run.conclude!(summary: "Checkout writes time out", suggest_incident: true)

    buttons = Slack::Messages::InvestigationRun.finding(finding: finding).select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }

    declare = buttons.find { |button| button[:action_id] == Identifiers::DECLARE_INCIDENT_FROM_INVESTIGATION }
    assert_equal run.id, declare[:value]
  end

  test "an answer on an incident never offers to declare another, even when the agent asks to" do
    run = @incident.workspace.investigations.create!(
      subject: incidents(:active_major_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    finding = run.conclude!(summary: "Checkout writes time out", suggest_incident: true)

    buttons = Slack::Messages::InvestigationRun.finding(finding: finding).select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }

    assert_nil buttons.find { |button| button[:action_id] == Identifiers::DECLARE_INCIDENT_FROM_INVESTIGATION }
    assert_not finding.suggests_incident
  end

  test "a question that stopped on our side offers to ask it again" do
    run = @incident.workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )

    blocks = Slack::Messages::InvestigationRun.stopped(reason: Investigation::GAVE_UP, rerun_question: run)

    button = blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }.sole
    assert_equal [ Identifiers::RERUN_INVESTIGATION_QUESTION, run.id ], [ button[:action_id], button[:value] ]
  end

  test "an incident declared from an answer opens with it, naming the question" do
    run = @incident.workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
    finding = run.conclude!(summary: "Checkout writes time out")

    text = Slack::Messages::InvestigationRun.carried_over(finding: finding).first.dig(:text, :text)

    assert_match "Declared from an investigation", text
    assert_match "checkout is slow", text
  end

  test "the opening message names the incident and who asked" do
    text = Slack::Messages::InvestigationRun.started(incident: @incident, started_by: "Alice").sole.dig(:text, :text)

    assert_match @incident.identifier, text
    assert_match "Started by Alice", text
  end

  test "an answer carries the evidence, the gaps and a right, partly right or wrong rating" do
    blocks = Slack::Messages::InvestigationRun.finding(finding: @finding)

    assert_equal "*14:02 deploy* raised the pool size", blocks.first.dig(:text, :text).split("The ").last
    assert_match "• The commit raised the pool size _(Commit lookup abc123)_", blocks.second.dig(:text, :text)
    assert_match "production logs", blocks.third[:elements].sole[:text]

    assert_equal "Was this answer right?", blocks[-2][:elements].sole[:text]
    buttons = blocks.last[:elements]
    assert_equal "actions", blocks.last[:type]
    assert_equal [ "Right", "Partly right", "Wrong" ], buttons.map { |button| button.dig(:text, :text) }
    assert_equal [ Identifiers::RATE_INVESTIGATION_RIGHT, Identifiers::RATE_INVESTIGATION_PARTLY, Identifiers::RATE_INVESTIGATION_WRONG ],
                 buttons.map { |button| button[:action_id] }
    assert_equal Investigation::Finding::OUTCOMES.map { |outcome| "#{@finding.id}:#{outcome}" }, buttons.map { |button| button[:value] }
  end

  test "an answer with a fix lists its steps in order, saying how each gets done, and how to tell it worked" do
    Investigation::RemediationPlan.propose!(@finding, { "summary" => "Roll back the **14:02 deploy**", "verify" => "Pool waits back under 50ms",
                                                        "steps" => [ { "kind" => "pull_request", "description" => "Revert the pool size", "repository" => "acme/api" },
                                                                     { "kind" => "manual", "description" => "Restart the workers" } ] })

    text = Slack::Messages::InvestigationRun.finding(finding: @finding.reload).map { |block| block.dig(:text, :text) }.compact.find { |each| each.start_with?("*How to fix it*") }

    assert_equal "*How to fix it*\nRoll back the *14:02 deploy*\n1. _Code change in `acme/api`_ Revert the pool size\n2. _For a person_ Restart the workers\n" \
                 "_How to tell it worked:_ Pool waits back under 50ms", text
  end

  test "an answer and a stop both link to the run in Firefight, where every step and receipt is" do
    with_app_host do
      investigation = @finding.investigation
      answer_link = Slack::Messages::InvestigationRun.finding(finding: @finding).find { |block| block[:type] == "actions" }
      stop_link = Slack::Messages::InvestigationRun.stopped(reason: "Budget spent before it could answer", investigation: investigation).last

      expected = "https://app.example.com/app/investigations/#{investigation.id}"
      assert_equal expected, answer_link[:elements].sole[:url]
      assert_equal expected, stop_link[:elements].sole[:url]
    end
  end

  test "a run that stopped on our side offers one button to run it again" do
    blocks = Slack::Messages::InvestigationRun.stopped(reason: "Something went wrong on my side", rerun: @incident)

    button = blocks.last[:elements].sole
    assert_equal "actions", blocks.last[:type]
    assert_equal Identifiers::START_INVESTIGATION, button[:action_id]
    assert_equal @incident.id, button[:value]
  end

  test "a run that stopped for its own reasons offers no button, since running it again would end the same way" do
    blocks = Slack::Messages::InvestigationRun.stopped(reason: "Budget spent before it could answer")

    assert_equal [ "section" ], blocks.map { |block| block[:type] }
  end

  test "an answer with nothing to cite leaves the evidence out rather than showing an empty list" do
    finding = @finding.investigation.finding
    finding.evidence_items.destroy_all
    finding.update!(gaps: nil)

    blocks = Slack::Messages::InvestigationRun.finding(finding: finding)

    assert_equal [ "section", "context", "actions" ], blocks.map { |block| block[:type] }
    assert_equal Identifiers::RATE_INVESTIGATION_RIGHT, blocks.last[:elements].first[:action_id]
  end

  test "an answer whose fix runs through a connection offers Apply fix, which asks first, and one already applied does not" do
    plan = build_fix_plan(@incident.workspace)

    button = apply_button(plan)
    assert_equal [ Identifiers::APPLY_FIX, plan.id ], [ button[:action_id], button[:value] ]
    assert_equal "Runs 1 step through your connections, as you, in order. 2 steps for a person are marked done in the thread.",
                 button.dig(:confirm, :text, :text)

    plan.apply!(by: workspace_memberships(:alice_workspace_one), from: AbilityGateway::SOURCE_WEB)
    assert_nil apply_button(plan.finding.reload.remediation_plan)
  end

  private

  def apply_button(plan)
    Slack::Messages::InvestigationRun.finding(finding: plan.finding).select { |block| block[:type] == "actions" }
                                     .flat_map { |block| block[:elements] }.find { |element| element[:action_id] == Identifiers::APPLY_FIX }
  end

  def with_app_host
    previous = ENV["APP_HOST"]
    ENV["APP_HOST"] = "app.example.com"
    yield
  ensure
    ENV["APP_HOST"] = previous
  end
end
