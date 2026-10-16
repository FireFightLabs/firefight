require "application_system_test_case"

class WorkflowSandboxStepsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Check the shop")
  end

  test "a browser step's path is set up step by step, and letting a step send asks how to undo it" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Browser" }
    assert_toast "Browser was added."
    fill_in "Address", with: "https://shop.example.com"
    click_button "Add a step"
    find("input[aria-label='What it clicks, by its text']").fill_in(with: "Buy now")
    find("button[role=combobox][aria-label='The step allowed to send']").click
    find("[role=option]", text: "Let step 1 send what the page sends").click
    assert_text "How a person puts it back"
    fill_in "How a person puts it back", with: "Cancel the test order."
    take_screenshot
    using_wait_time(10) { assert_no_selector "[data-sonner-toast]" }
    click_button "Apply changes"

    assert_toast "Browser was updated."
    config = @workflow.reload.draft.steps.sole["config"]
    assert_equal [ "https://shop.example.com", [ { "action" => "click", "text" => "Buy now" } ], 1, "Cancel the test order." ],
                 config.values_at("url", "steps", "send_step", "undo")
  end

  test "a command asks how to undo it only once it says it changes something" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Run command" }
    assert_toast "Run command was added."
    assert_no_selector "label", text: /\Aundo/
    find("button[role=switch][id$='-changes']").click
    assert_selector "label", text: /\Aundo/
    take_screenshot
  end
end
