require "application_system_test_case"

class WorkflowIncidentStepsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Calm the incident")
  end

  test "update incident asks only what the change it makes needs" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Update incident" }
    assert_toast "Update incident was added."
    assert_selector "label", text: "severity"
    assert_no_selector "label", text: "member"

    find("button[role=combobox]", text: "severity").click
    find("[role=option]", text: "lead").click
    assert_selector "label", text: "member"
    assert_no_selector "label", text: /\Aseverity/
    take_screenshot
  end

  test "classify offers a way out for each route it sorts into" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: workspace_memberships(:alice_workspace_one),
                    payload: { "step" => { "id" => "sort", "name" => "sort", "kind" => "classify",
                                           "config" => { "data" => "{{trigger}}", "routes" => %w[noise outage], "otherwise" => "other" } } })
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("[data-step='sort']") do
      assert_text "noise"
      assert_text "outage"
      assert_text "other"
    end
    take_screenshot
  end
end
