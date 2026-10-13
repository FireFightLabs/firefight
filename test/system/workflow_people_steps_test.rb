require "application_system_test_case"

class WorkflowPeopleStepsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release")
    @draft = @workflow.open_draft!(by: @alice)
    adapter = WorkspaceAdapter.for(@workspace).class
    adapter.any_instance.stubs(:post_workflow_question).returns({ channel_id: "D-BOB", message_id: "1.1" })
    adapter.any_instance.stubs(:update_workflow_question).returns({ success: true })
    adapter.any_instance.stubs(:post_approval_request).returns({ channel_id: "C-OPS", message_id: "2.2" })
    adapter.any_instance.stubs(:mark_approval_resolved).returns({ success: true })
  end

  def step(id, kind, config = {}) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def try!(*steps)
    @draft.update!(steps: steps, edges: [])
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(@workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true) }
    run.reload
  end

  test "an approval asks who approves, and the incident's conditions only once it names one" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Approval" }
    assert_toast "Approval was added."
    assert_selector "label", text: /\Arole/
    assert_no_selector "label", text: /\Aapprovers/
    assert_no_text "Add a condition the incident must still meet"

    find("button[role=combobox]", text: "role").click
    find("[role=option]", text: "people").click
    assert_selector "label", text: /\Aapprovers/
    find("[id$='-incident']").fill_in(with: "{{trigger.incident.identifier}}")
    assert_text "Add a condition the incident must still meet"
    click_button "Add a condition"
    take_screenshot
  end

  test "ask a person takes a short form beside its choices, and set data and stop take theirs" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Ask a person" }
    assert_toast "Ask a person was added."
    click_button "Add a field"
    find("input[aria-label='Name']").fill_in(with: "reason")
    find("input[aria-label='What it asks']").fill_in(with: "Why roll back?")
    take_screenshot

    within("aside[aria-label='Add a step']") { click_button "Set data" }
    assert_toast "Set data was added."
    assert_button "Add a value"
    take_screenshot

    within("aside[aria-label='Add a step']") { click_button "Stop" }
    assert_toast "Stop was added."
    assert_selector "label", text: /\Aoutcome/
    take_screenshot
  end

  test "the person testing answers a question on the run's page, and the run takes the route of the choice" do
    run = try!(step("ask", "ask_person", { "to" => "person", "person" => "bob@example.com", "question" => "Ship the fix?", "choices" => %w[ship_it wait] }))
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow, run: run.id)

    find("[data-step='ask']").click
    within("aside[aria-label='Run']") do
      assert_text "Ship the fix?"
      assert_text "Asked of"
      take_screenshot
    end
    perform_enqueued_jobs do
      within("aside[aria-label='Run']") { click_button "Ship it" }
      assert_toast "Your answer to Release was sent."
    end
    assert_equal "ship_it", run.reload.steps.find_by!(step_key: "ask").route
  end

  test "an approver approves on the run's page" do
    run = try!(step("approve", "approval", { "question" => "Release checkout?", "who" => "people", "approvers" => [ "alice@example.com" ] }))
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow, run: run.id)

    find("[data-step='approve']").click
    within("aside[aria-label='Run']") do
      assert_text "Release checkout?"
      take_screenshot
    end
    perform_enqueued_jobs do
      within("aside[aria-label='Run']") { click_button "Approve" }
      assert_toast "You approved Release's request. The run goes on."
    end
    assert_equal "approved", run.reload.steps.find_by!(step_key: "approve").route
  end
end
