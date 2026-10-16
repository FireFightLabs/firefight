require "application_system_test_case"

# What keeps a workflow from running away, as its page shows it: its most runs per hour and the runs skipped past it,
# the check a change makes first, and what a run spent on AI and on its sandbox.
class WorkflowRunLimitsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_failure).returns({})
    @workflow = Workflow.create!(workspace: @workspace, name: "Restart web", created_by: @alice)
  end

  def restart = { "id" => "restart", "name" => "restart", "kind" => "call_tool",
                  "config" => { "tool" => "restart", "arguments" => { "resource" => "web" }, "undo" => "Roll web back." } }

  def look = { "id" => "look", "name" => "look", "kind" => "call_tool", "config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => {} } }

  def drafted!
    @workflow.open_draft!(by: @alice).update!(steps: [ restart, look ], edges: [ { "from" => "restart", "to" => "look" } ])
    @workflow.reload
  end

  test "the most runs per hour is set in the settings, and runs skipped past it show on the page with how many and when" do
    travel_to(1.hour.ago.beginning_of_hour + 5.minutes) { 3.times { @workflow.run_skipped! } }
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("[data-testid='skipped-runs']") do
      assert_text "3 runs were skipped in the last week because it had already started as many runs in the hour before as it allows."
      assert_text "3 skipped, the last at"
    end

    find("[role=radio]", text: "Settings").click
    assert_field "Most runs per hour", with: "100"
    fill_in "Most runs per hour", with: "250"
    click_button "Save settings"
    assert_toast "Restart web was updated."
    assert_equal 250, @workflow.reload.runs_per_hour
  end

  test "a change step switches off checking it is still needed first, saying so" do
    drafted!
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    find("[data-step='restart']").click
    within("aside[aria-label='Step settings']") do
      assert_text(/before it changes something/i)
      assert_selector "#step-restart-check-first[role=switch][aria-checked=true]"
      find("#step-restart-check-first[role=switch]").click
      click_button "Apply changes"
    end
    assert_toast "Restart was updated."
    assert_equal false, @workflow.reload.draft.steps.find { |step| step["id"] == "restart" }["config"]["check_first"]

    find("[data-step='look']").click
    within("aside[aria-label='Step settings']") { assert_no_text "Check it is still needed first" }
  end

  test "a run shows what it spent on AI and on its sandbox apart, and why a change was skipped" do
    drafted!
    Workflow::NeedCheck.stubs(:run).returns(Workflow::NeedCheck::Verdict.new(state: "web answers 200 again since 14:02.", verdict: Workflow::NeedCheck::CLEARED))
    WorkflowPublishService.new(@workflow).publish!(@workflow.draft, by: @alice)
    @workflow.reload.update!(cost_cap_cents: 500)
    run = nil
    perform_enqueued_jobs do
      run = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: Workflow::Trigger::KIND_ALERT_RECEIVED,
                                                     trigger_payload: { "alert" => { "title" => "web answers 503" } })
    end
    Inference.create!(workspace: @workspace, inferable: run.steps.find_by!(step_key: "restart"), feature: FirefightAi::NeedChecker::FEATURE, provider: "openai",
                      model: "gpt", cost_micros: 31_000, status: "success")
    CodeBox.create!(workspace: @workspace, key: run.code_box_key, provider: SandboxProviders::BOAT, box_ref: "bx_1", address: "https://box.example.com",
                    secret: "k", last_used_at: Time.current, box_started_at: 1.hour.ago, hourly_micros: 120_000, stopped_at: Time.current, running_seconds: 3600)
    run.steps.find_by!(step_key: "look").update!(sandbox_seconds: 42, sandbox_micros: 1_400)
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow, run: run.id)

    within("aside[aria-label='Run']") do
      within("[aria-label='What it spent']") do
        assert_text "AI\n$0.03"
        assert_text "Sandbox\n$0.12"
        assert_text "Ceiling\n$5"
      end
      assert_text "restart: Halon checked first and the problem has cleared, so this step did not run. web answers 200 again since 14:02."
    end

    find("[data-step='restart']").click
    within("aside[aria-label='Run']") { assert_text "Halon checked first and the problem has cleared" }
    find("[data-step='look']").click
    within("aside[aria-label='Run']") { assert_text "Used the sandbox for 42 seconds, which cost under $0.01." }
  end
end
