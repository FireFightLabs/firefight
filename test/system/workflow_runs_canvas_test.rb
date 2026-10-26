require "application_system_test_case"

class WorkflowRunsCanvasTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  RESIZE_HANDLE = "[role=separator][aria-label='Resize the panel']".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
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
    # The editor view shows at once, but the draft and its Test run arrive only with the server's answer, which drops
    # the run from the address.
    assert_current_path workflow_path(@workflow), wait: 15
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

    # Opening a run is a visit the server draws, which on a loaded runner takes longer than Capybara's default two
    # seconds. The address carries the run only once the server answered, so wait for that before reading the page.
    assert_current_path(/run=/, wait: 15)
    assert_text "Test run of v1"
    assert_text "Pick a step here or on the canvas for everything it did."
  end

  test "the panel beside the canvas widens from its edge, keeps its width after a reload and in the editor, and resets" do
    steps!(step("pause", "delay", { "seconds" => 0 }))
    run = try!
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow, run: run.id)

    default = panel_width("Run")
    page.driver.browser.action.drag_and_drop_by(find(RESIZE_HANDLE).native, -200, 0).perform
    assert_no_selector "#{RESIZE_HANDLE}[aria-valuenow='#{default}']"
    wider = panel_width("Run")
    assert_in_delta default + 200, wider, 2

    find(RESIZE_HANDLE).send_keys(:arrow_left)
    assert_selector "#{RESIZE_HANDLE}[aria-valuenow='#{wider + 16}']"

    refresh
    assert_text "Test run of v1"
    assert_selector "#{RESIZE_HANDLE}[aria-valuenow='#{wider + 16}']"
    assert_equal wider + 16, panel_width("Run")
    find("[data-step='pause']").click
    within("aside[aria-label='Run']") { assert_text "The whole run" }
    assert_equal wider + 16, panel_width("Run")

    click_button "Back to the editor"
    assert_current_path workflow_path(@workflow), wait: 15
    assert_equal wider + 16, panel_width("Step settings")

    find(RESIZE_HANDLE).double_click
    assert_selector "#{RESIZE_HANDLE}[aria-valuenow='#{default}']"
    assert_equal default, panel_width("Step settings")

    page.current_window.resize_to(390, 844)
    assert_no_selector RESIZE_HANDLE
  end

  def panel_width(label)
    find("aside[aria-label='#{label}']").evaluate_script("this.offsetWidth")
  end
end
