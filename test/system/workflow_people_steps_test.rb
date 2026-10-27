require "application_system_test_case"

class WorkflowPeopleStepsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
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

    # Stop is added below Set data and then connected to it. On a fast runner the second toast hides the first's words
    # behind it, and on a slow one the first has gone before the second arrives, so the page records each toast it draws.
    record_toasts
    within("aside[aria-label='Add a step']") { click_button "Stop" }
    assert_toast "Set data now leads to Stop."
    assert_toast_drawn "Stop was added."
    assert_selector "label", text: /\Aoutcome/
    take_screenshot
  end

  test "ask a person's choices are the words on their buttons, keyed once and kept, and it waits as long as it says" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Ask a person" }
    assert_toast "Ask a person was added."
    assert_no_text "Time limit in seconds"
    assert_field "Wait for", with: "1"
    click_button "Add a choice"
    find("input[aria-label='Words on the button']").fill_in(with: "Roll back now")
    find("[id$='-question']").fill_in(with: "Roll back checkout?")
    find("[id$='-person']").fill_in(with: "bob@example.com")
    fill_in "Wait for", with: "3"
    find("button[aria-label='Wait unit']").click
    find("[role=option]", text: "Hours").click
    click_button "Apply changes"
    assert_toast "Ask a person was updated."
    assert_selector "[data-step='ask_a_person']", text: "Roll back now"
    take_screenshot

    config = @workflow.reload.draft.steps.sole["config"]
    assert_equal [ { "key" => "roll_back_now", "label" => "Roll back now" } ], config["choices"]
    assert_equal 180, config["wait_minutes"]

    # The second save says it happened with the same words, so the first toast has to be gone before it can prove
    # anything. It stays while the pointer rests on it.
    find("header h1", text: "Release").hover
    assert_no_selector "[data-sonner-toast]", wait: 10
    find("input[aria-label='Words on the button']").fill_in(with: "Roll back at once")
    click_button "Apply changes"
    assert_toast "Ask a person was updated."
    assert_equal [ { "key" => "roll_back_now", "label" => "Roll back at once" } ], @workflow.reload.draft.steps.sole.dig("config", "choices")
  end

  test "a manual step asks for its task, who does it, the note it collects and how long it waits" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Manual step" }
    assert_toast "Manual step was added."
    assert_selector "label", text: /\Atask/
    assert_selector "label", text: /\Anote/
    assert_field "Wait for", with: "1"
    find("button[role=combobox]", text: "person").click
    find("[role=option]", text: "anyone").click
    assert_selector "label", text: /\Aincident/
    assert_no_selector "label", text: /\Aperson/
    take_screenshot
  end

  test "the person testing marks a task done on the run's page with the note it collects" do
    adapter = WorkspaceAdapter.for(@workspace).class
    adapter.any_instance.stubs(:post_workflow_question_in_channel).returns({ channel_id: "C-OPS", message_id: "3.3" })
    run = try!(step("ticket", "manual", { "task" => "Open a ticket with the payment provider.", "to" => "person", "person" => "bob@example.com", "note" => "Ticket number" }))
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow, run: run.id)

    find("[data-step='ticket']").click
    within("aside[aria-label='Run']") do
      assert_text "Open a ticket with the payment provider."
      assert_text "Given to"
      click_button "Done"
    end
    within("[role=dialog]") do
      fill_in "Ticket number", with: "PAY-412"
      take_screenshot
    end
    perform_enqueued_jobs do
      within("[role=dialog]") { click_button "Mark done" }
      assert_toast "You marked Release's task done."
    end
    assert_equal({ "done_by" => @alice.actor_display_name, "note" => "PAY-412" }, run.reload.steps.find_by!(step_key: "ticket").output)
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

  test "a member an approval names decides it on the Approvals page, and every other request says why they cannot" do
    named = try!(step("approve", "approval", { "question" => "Release checkout?", "who" => "people", "approvers" => [ "bob@example.com" ] }))
    try!(step("approve", "approval", { "question" => "Release payments?", "who" => "role", "role" => "admin" }))
    sign_in(users(:bob), @workspace)
    visit gateway_approvals_path

    row = find("tr", text: "Release checkout?")
    other = find("tr", text: "Release payments?")
    assert row.find_button("Approve").matches_css?(":not([disabled])")
    assert other.find_button("Approve", disabled: true)
    take_screenshot
    perform_enqueued_jobs do
      row.click_button "Approve"
      assert_toast "approved"
    end
    assert_equal "approved", named.reload.steps.find_by!(step_key: "approve").route
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
