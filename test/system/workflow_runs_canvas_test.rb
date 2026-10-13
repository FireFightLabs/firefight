require "application_system_test_case"

class WorkflowRunsCanvasTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    @draft = @workflow.open_draft!(by: @alice)
  end

  def step(id, kind, config = {}, **extra) = { "id" => id, "name" => id, "kind" => kind, "config" => config }.merge(extra.stringify_keys)

  def steps!(*steps, edges: [])
    @draft.update!(steps: steps, edges: edges)
    @workflow.reload
  end

  def try!
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(@workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true) }
    run.reload
  end

  test "a test run starts from the canvas and opens with each step's state and what it gave" do
    steps!(step("wait_a_bit", "delay", { "seconds" => 0 }), step("then_more", "delay", { "seconds" => 0 }), edges: [ { "from" => "wait_a_bit", "to" => "then_more" } ])
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    click_button "Test run"
    within("[role=dialog]") { fill_in "What started the run, as JSON", with: '{ "service": "web" }' }
    perform_enqueued_jobs do
      within("[role=dialog]") { click_button "Start test run" }
      assert_toast "Release check is being tried."
    end

    assert_text "Test run of v1"
    within("[data-step='wait_a_bit']") { assert_text "s" }
    find("[data-step='wait_a_bit']").click
    within("aside[aria-label='Run']") do
      assert_text "What it gave"
      assert_text "waited_until"
    end
    assert_equal({ "service" => "web" }, @workflow.runs.sole.trigger_payload)
  end

  test "a failed step is tried again from the run's view, and a step's output is pinned from it" do
    steps!(step("broken", "delay", { "at" => "not a moment" }, retry: { "max_attempts" => 1 }, on_failure: "continue"),
           step("pause", "delay", { "seconds" => 0 }))
    run = try!
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow, run: run.id)

    find("[data-step='broken']").click
    within("aside[aria-label='Run']") do
      assert_text "Delay needs a moment it can read"
      click_button "Try again"
    end
    assert_toast "Broken is being tried again."
    # The toast sits over the panel's buttons and stays while the pointer rests on it.
    find("header h1", text: "Release check").hover
    assert_no_selector "[data-sonner-toast]", wait: 10

    find("[data-step='pause']").click
    within("aside[aria-label='Run']") { click_button "Pin this output" }
    assert_toast "Pause's output is pinned."

    click_button "Back to the editor"
    assert_button "Test run"
    find("[data-step='pause']").click
    within("aside[aria-label='Step settings']") { assert_text "Test runs use it in the step's place." }
  end

  test "a test run acts as the tester and shows a change it was not told to make, rather than making it" do
    steps!(step("tell", "post_to_channel", { "channel" => "#ops", "message" => "Hello" }))
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    click_button "Test run"
    perform_enqueued_jobs do
      within("[role=dialog]") { click_button "Start test run" }
      assert_toast "Release check is being tried."
    end
    find("[data-step='tell']").click

    within("aside[aria-label='Run']") { assert_text "Shown, not made." }
    run = @workflow.runs.sole
    assert_equal workspace_memberships(:alice_workspace_one), run.acting_principal
    assert_empty run.real_step_keys
  end

  test "the Runs view lists every run and opens one on the canvas" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    try!
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    find("[role=radio]", text: "Runs").click
    click_button "Test run of version 1"

    assert_text "Test run of v1"
    assert_text "Pick a step on the canvas to see what it took in, gave back and called."
  end
end
