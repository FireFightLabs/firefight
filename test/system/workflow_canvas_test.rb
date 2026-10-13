require "application_system_test_case"

class WorkflowCanvasTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Weekday probe check")
    WorkspaceAdapter.stubs(:for).returns(stub(post_workflow_publish_request_to_user: { channel_id: "D1", message_id: "1.1" },
                                              update_workflow_publish_request: { success: true },
                                              post_workflow_publish_answer_to_user: { channel_id: "D2", message_id: "2.1" }))
  end

  def delay(id, name = id, minutes = 5) = { "id" => id, "name" => name, "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => minutes } }

  def add(step, by: @alice, **options) = @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => step }, by: by, **options)

  test "a member adds a step from the palette and sets it up, each change saying so" do
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Delay" }
    assert_toast "Delay was added."
    assert_selector "[data-step='delay']"

    fill_in "How long", with: "45"
    click_button "Apply changes"
    assert_toast "Delay was updated."
    assert_equal({ "minutes" => 45 }, @workflow.reload.draft.steps.sole["config"])
  end

  test "a step is removed after asking, with what goes with it" do
    add(delay("wait", "wait_a_bit"))
    add(delay("later"))
    @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_CONNECT, payload: { "from" => "wait", "to" => "later" }, by: @alice)
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    find("[data-step='wait_a_bit']").click
    click_button "Remove step"
    assert_text "It leaves the draft with its connection."
    within("[role=dialog]") { click_button "Remove step" }

    assert_toast "Wait a bit was removed."
    assert_no_selector "[data-step='wait_a_bit']"
  end

  test "a change to a step someone changed since is refused, naming them" do
    add(delay("wait", "wait_a_bit"))
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)
    find("[data-step='wait_a_bit']").click
    fill_in "How long", with: "12"

    draft = @workflow.reload.draft
    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { "step_id" => "wait", "changes" => { "config" => { "minutes" => 9 } } },
                    by: @alice, base_revision: draft.revision)
    click_button "Apply changes"

    assert_toast "Alice Smith changed this since you looked, so look again before changing it."
    assert_equal({ "minutes" => 9 }, @workflow.reload.draft.steps.sole["config"])
  end

  test "a member asks an admin to publish, and the admin publishes the draft" do
    add(delay("wait"), by: @bob)
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    click_button "Ask an admin to publish"
    assert_toast "Asked Alice Smith to publish Weekday probe check."
    assert_button "Asked an admin", disabled: true

    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)
    assert_text "Bob Jones asked on"
    click_button "Publish v1"
    within("[role=dialog]") { click_button "Publish" }

    assert_toast "Weekday probe check was published."
    assert_text "Live · v1"
    assert Workflow::PublishRequest.find_by!(workflow: @workflow, requester: @bob).published_at
  end

  test "Halon's suggested step is accepted from the canvas, and the rest dismissed at once" do
    add(delay("wait"))
    @workflow.reload.draft.publish!(by: @alice)
    @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("tell", "tell_ops") }, by: nil, halon: true,
                           reason: "Someone should hear once it waited.")
    @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { "step_id" => "wait", "changes" => { "config" => { "minutes" => 30 } } },
                           by: nil, halon: true, reason: "Five minutes was too short.")
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    assert_text "2 suggestions from Halon"
    within("[data-step='tell_ops']") { click_button "Add step" }
    assert_toast "Halon's suggestion to add Tell ops was accepted."

    click_button "Dismiss all"
    assert_toast "Halon's suggestion was dismissed."
    assert_empty @workflow.proposals
    assert_equal %w[wait tell], @workflow.reload.draft.steps.map { |step| step["id"] }
  end

  test "Halon's change is undone from Changes by Halon" do
    add(delay("wait"), by: nil, halon: true, reason: "Wait before checking.")
    add(delay("check"))
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    click_button "Changes by Halon"
    within("section[aria-label='Changes by Halon']") do
      assert_text "Halon added Wait."
      click_button "Undo"
    end

    assert_toast "Halon's change was undone."
    assert_equal [ "check" ], @workflow.reload.draft.steps.map { |step| step["id"] }
  end

  test "an old version opens read only, and restoring it waits for the open draft" do
    add(delay("wait"))
    @workflow.reload.draft.publish!(by: @alice)
    add(delay("later"))
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    find("[role=radio]", text: "Versions").click
    within("li", text: "Version 1") { click_button "Open" }
    assert_text "Live · v1"
    assert_no_selector "[data-step='later']"

    find("[role=radio]", text: "Versions").click
    within("li", text: "Version 1") { assert_button "Restore", disabled: true }
  end

  test "an old version's schedule and watch show read only" do
    watch = { "id" => "follow", "name" => "follow_web", "kind" => DefinedWorkflow::Steps::Watch.kind,
              "config" => { "title" => "Deploy of web", "steps" => [ { "label" => "web", "capability" => "status", "resource" => "web", "done_when" => "running" } ] } }
    add(watch)
    schedule = Workflow::TriggerKinds.find(Workflow::Trigger::KIND_SCHEDULE).defaults.merge("kind" => Workflow::Trigger::KIND_SCHEDULE, "time_zone" => "UTC")
    @workflow.reload.draft.update!(trigger: schedule)
    @workflow.reload.draft.publish!(by: @alice)
    add(delay("later"))
    @workflow.reload.draft.publish!(by: @alice)
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)
    find("[role=radio]", text: "Versions").click
    within("li", text: "Version 1") { click_button "Open" }
    assert_no_selector "[data-step='later']"

    find("[data-step='follow_web']").click
    assert_selector "input[aria-label='Watch 1 label'][disabled]"
    assert_no_button "Remove watch 1"

    find("div", text: "On a schedule", match: :first).click
    assert_button "Mon", disabled: true
    assert_selector "#trigger-schedule-zone[disabled]"
  end

  test "on a phone the steps are a list, each opening its settings" do
    add(delay("wait", "wait_a_bit"))
    page.current_window.resize_to(390, 844)
    sign_in(users(:bob), @workspace)
    visit workflow_path(@workflow)

    find("button", text: "Wait a bit").click
    assert_field "How long", with: "5"

    click_button "Close"
    click_button "Add a step"
    within("[role=dialog]") { click_button "Wait for event" }
    assert_toast "Wait for event was added."
  end
end
