require "test_helper"

class Slack::Messages::InvestigationRunTest < ActiveSupport::TestCase
  include FixPlanTestHelper
  setup do
    @incident = incidents(:active_critical_ws1)
    @incident.workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
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

  test "a question with no incident is named by its own words, plain in a plan's title and escaped where it is markup" do
    run = @incident.workspace.investigations.create!(trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
                                                     brief: { Investigation::Brief::KEY_SYMPTOM => "is <checkout> slow" })
    progress = Investigation::Progress.new(run)

    rich = Slack::Messages::InvestigationRun.checklist(progress: progress, incident: nil, question: "is <checkout> slow", started_by: "Alice")
    plain = Slack::Messages::InvestigationRun.checklist(progress: progress, incident: nil, question: "is <checkout> slow", started_by: "Alice", rich: false)

    assert_equal "Investigating \"is <checkout> slow\"", rich.first[:title]
    assert_match "is &lt;checkout&gt; slow", plain.first.dig(:text, :text)
  end

  test "the checklist marks each task by Slack's status, says who started it and links to the run" do
    with_app_host do
      run = @finding.investigation
      run.steps.create!(position: 2, tool_name: "search_logs", action_key: "grafana.search_logs", status: Investigation::Step::STATUS_RUNNING)
      run.steps.create!(position: 3, tool_name: "query_metrics", action_key: "grafana.query_metrics", status: Investigation::Step::STATUS_FAILED,
                        failure_kind: Chat::StepOutcome::FAILURE_ERROR)
      live = Investigation::Progress.new(run)
      live.define_singleton_method(:finding) { nil }

      blocks = Slack::Messages::InvestigationRun.checklist(progress: live, incident: @incident, started_by: "Alice")

      assert_equal [ [ "Gathered what Firefight knows", "complete" ], [ "Read the code", "complete" ], [ "Read the logs and metrics", "in_progress" ],
                     [ "Find the cause", "pending" ] ], blocks.first[:tasks].map { |task| task.values_at(:title, :status) }
      assert_equal "Started by Alice  ·  Halon is working in the thread", blocks.second.dig(:elements, 0, :text)
      assert_equal "https://app.example.com/app/investigations/#{run.id}", blocks.third.dig(:elements, 0, :url)

      stopped = Slack::Messages::InvestigationRun.checklist(progress: Investigation::Progress.new(run.tap { |each| each.finding.destroy! }.reload, stop_reason: Investigation::BUDGET_SPENT),
                                                            incident: @incident, started_by: "Alice")
      assert_equal "Investigation of #{@incident.identifier} stopped", stopped.first[:title]
      assert_equal [ "error", "complete" ], stopped.first[:tasks].values_at(-1, -3).pluck(:status)
      assert_equal "Budget spent before it could answer", stopped.first[:tasks].last.dig(:output, :elements, 0, :elements, 0, :text)
    end
  end

  test "a run reading many kinds of system keeps its checklist to a handful, the rest counted as other checks" do
    run = @finding.investigation
    %w[search_logs recent_deploys check_in_browser get_resource_map].each_with_index do |tool, index|
      run.steps.create!(position: index + 2, tool_name: tool, action_key: (tool == "get_resource_map" ? "map.read" : "x.#{tool}"),
                        status: Investigation::Step::STATUS_SUCCEEDED)
    end
    run.steps.create!(position: 9, tool_name: "unknown_tool", action_key: "nowhere.unknown_tool", status: Investigation::Step::STATUS_SUCCEEDED)

    titles = Investigation::Progress.new(run).tasks.map(&:title)

    assert_equal [ "Gathered what Firefight knows", "Read the code", "Read the logs and metrics", "Checked recent deploys",
                   "Checked the page in a browser", "Ran other checks", @finding.headline ], titles  end

  test "an answer that says users are hurt now, with no incident, offers to declare one" do
    run = @incident.workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
    finding = run.conclude!(summary: "Checkout writes time out", suggest_incident: true)

    buttons = Slack::Messages::InvestigationRun.answer(finding: finding).select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }

    declare = buttons.find { |button| button[:action_id] == Identifiers::DECLARE_INCIDENT_FROM_INVESTIGATION }
    assert_equal run.id, declare[:value]
  end

  test "an answer on an incident never offers to declare another, even when the agent asks to" do
    run = @incident.workspace.investigations.create!(
      subject: incidents(:active_major_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    finding = run.conclude!(summary: "Checkout writes time out", suggest_incident: true)

    buttons = Slack::Messages::InvestigationRun.answer(finding: finding).select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements] }

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

  test "the short answer is a handful of plain lines: the kind and how sure, what is wrong, three facts, the fix and what was not checked" do
    run = @incident.workspace.investigations.create!(subject: incidents(:active_major_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                     max_turns: 10, max_spend_cents: 400)
    run.steps.create!(position: 1, tool_name: "search_logs", action_key: "grafana.search_logs", status: Investigation::Step::STATUS_SUCCEEDED)
    run.record_hypothesis!(assertion: "The pool is too small", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    finding = run.conclude!(
      summary: "`config/database.yml` sets `pool: 5` and `CheckoutJob#perform` holds a connection per item",
      hypothesis_assertion: "The pool is too small",
      evidence: (1..4).map { |index| { claim: "`app/jobs/checkout_job.rb:#{index}` holds a connection", plain: "Fact #{index} in plain words", steps: [ 1 ] } },
      gaps: "The database's own logs at `pg-primary-1`, since the read was refused, and the replica, since nothing reaches it",
      fix: { "summary" => "Raise `pool` to 20 in config/database.yml", "steps" => [ { "kind" => "manual", "description" => "Edit config/database.yml" } ] },
      short: { answer_kind: Investigation::Finding::KIND_ROOT_CAUSE, confidence: 0.9, what_is_wrong: "Checkout runs out of database connections.",
               suggested_fix: "Give checkout more database connections.", not_checked: "the database's own logs" }
    )

    blocks = Slack::Messages::InvestigationRun.answer(finding: finding)
    text = blocks.to_json

    assert_equal ":dart:  *Root cause found*  ·  Very sure", blocks.first.dig(:text, :text)
    assert_equal "divider", blocks.second[:type]
    assert_equal "Checkout runs out of database connections.
• Fact 1 in plain words
• Fact 2 in plain words
• Fact 3 in plain words
" \
                 "*Suggested fix:* Give checkout more database connections.", blocks.third.dig(:text, :text)
    assert_equal "_Could not check: the database's own logs_", blocks.last.dig(:elements, 0, :text)
    assert_operator blocks.third.dig(:text, :text).lines.size, :<=, 6
    %w[config/database.yml checkout_job.rb CheckoutJob pg-primary-1 `].each { |code| assert_not_includes text, code }
  end

  test "a root cause the agent is not sure of reads as a likely one, and an answer with no cause says so without how sure" do
    @finding.update!(answer_kind: Investigation::Finding::KIND_ROOT_CAUSE, confidence: 0.5)
    assert_equal ":mag:  *Likely cause*  ·  Not very sure", Slack::Messages::InvestigationRun.answer(finding: @finding).first.dig(:text, :text)

    @finding.update!(answer_kind: Investigation::Finding::KIND_NO_CAUSE)
    assert_equal ":grey_question:  *No cause found yet*", Slack::Messages::InvestigationRun.answer(finding: @finding).first.dig(:text, :text)
  end

  test "the full answer in the thread carries the reasoning, the evidence with its sources, the gaps and a right, partly right or wrong rating" do
    blocks = Slack::Messages::InvestigationRun.answer_detail(finding: @finding)

    assert_equal [ ":page_facing_up:  *The full answer*", "divider" ], [ blocks.first.dig(:text, :text), blocks.second[:type] ]
    assert_equal "*14:02 deploy* raised the pool size", blocks.third.dig(:text, :text).split("The ").last
    assert_match "• The commit raised the pool size _(Commit lookup abc123)_", blocks.fourth.dig(:text, :text)
    assert_match "production logs", blocks.fifth[:elements].sole[:text]

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

    text = Slack::Messages::InvestigationRun.answer_detail(finding: @finding.reload).map { |block| block.dig(:text, :text) }.compact.find { |each| each.start_with?("*How to fix it*") }

    assert_equal "*How to fix it*\nRoll back the *14:02 deploy*\n1. _Code change in `acme/api`_ Revert the pool size\n2. _For a person_ Restart the workers\n" \
                 "_How to tell it worked:_ Pool waits back under 50ms", text
  end

  test "an answer and a stop both link to the run in Firefight, where every step and receipt is" do
    with_app_host do
      investigation = @finding.investigation
      answer_link = Slack::Messages::InvestigationRun.answer(finding: @finding).find { |block| block[:type] == "actions" }
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

  test "what a run did before it stopped follows the reason in its own section, escaped" do
    said = "What I did before I stopped:\n- Search logs <!channel>\nI stopped after the last of these, before I decided what to do next."
    blocks = Slack::Messages::InvestigationRun.stopped(reason: "Something went wrong on my side", where_it_stopped: said)

    assert_equal [ "section", "section" ], blocks.map { |block| block[:type] }
    assert_includes blocks.second[:text][:text], "- Search logs &lt;!channel&gt;"
  end

  test "a run that stopped for its own reasons offers no button, since running it again would end the same way" do
    blocks = Slack::Messages::InvestigationRun.stopped(reason: "Budget spent before it could answer")

    assert_equal [ "section" ], blocks.map { |block| block[:type] }
  end

  test "an answer with nothing to cite leaves the evidence out rather than showing an empty list" do
    finding = @finding.investigation.finding
    finding.evidence_items.destroy_all
    finding.update!(gaps: nil)

    detail = Slack::Messages::InvestigationRun.answer_detail(finding: finding)
    short = Slack::Messages::InvestigationRun.answer(finding: finding)

    assert_equal %w[section divider section context actions], detail.map { |block| block[:type] }
    assert_equal Identifiers::RATE_INVESTIGATION_RIGHT, detail.last[:elements].first[:action_id]
    assert_equal "The **14:02 deploy** raised the pool size", short.third.dig(:text, :text)
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
    Slack::Messages::InvestigationRun.answer(finding: plan.finding).select { |block| block[:type] == "actions" }
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
