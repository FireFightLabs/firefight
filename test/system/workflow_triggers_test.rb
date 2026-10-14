require "application_system_test_case"

class WorkflowTriggersTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Big incidents")
  end

  test "an incident trigger is chosen from the palette and narrowed with its changes and a condition" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Incident changed" }
    assert_toast "The trigger was updated."

    find("[data-trigger]").click
    within("[data-trigger-settings]") do
      assert_text "Severity"
      find("button[role=combobox]", text: "Add one").click
    end
    find("[role=option]", text: "Resolved").click
    click_button "Add a condition"
    find("button[role=combobox]", text: "What it reads").click
    find("[role=option]", text: "Severity").click
    find("button[role=combobox]", text: "Add a value").click
    find("[role=option]", text: "Critical").click
    take_screenshot
    using_wait_time(10) { assert_no_selector "[data-sonner-toast]" }
    click_button "Apply changes"

    assert_toast "The trigger was updated."
    trigger = @workflow.reload.draft.trigger
    assert_equal Workflow::Trigger::KIND_INCIDENT_CHANGED, trigger["kind"]
    assert_equal [ Workflow::Trigger::Changes::SEVERITY, Workflow::Trigger::Changes::RESOLVED ], trigger["changes"]
    assert_equal [ { "field" => "severity", "operator" => PolicyRule::OPERATOR_IS_ONE_OF, "value" => [ "critical" ] } ], trigger["conditions"]
    assert_text "Only when 1 condition holds"
  end

  test "an inbound webhook shows the workflow's own address, which is replaced after asking" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: workspace_memberships(:alice_workspace_one),
                    payload: { "trigger" => { "kind" => Workflow::Trigger::KIND_INBOUND_WEBHOOK, "inputs" => [] } })
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    find("[data-trigger]").click
    assert_selector "[data-hook-url]", text: @workflow.hook_token
    click_button "Add a condition"
    find("input[aria-label='What it reads']").fill_in(with: "body.service")
    find("input[aria-label='Values']").fill_in(with: "web, api")
    take_screenshot
    click_button "Apply changes"
    assert_toast "The trigger was updated."
    assert_equal [ { "field" => "body.service", "operator" => PolicyRule::OPERATOR_IS_ONE_OF, "value" => %w[web api] } ],
                 @workflow.reload.draft.trigger["conditions"]

    old = @workflow.hook_token
    click_button "Replace address"
    within("[role=dialog]") { click_button "Replace address" }
    assert_toast "Big incidents has a new webhook address and secret. The old ones no longer start it."
    assert_not_equal old, @workflow.reload.hook_token
  end

  test "a service scaled trigger is narrowed to a count above a number, and its steps read the counts" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Service scaled" }
    assert_toast "The trigger was updated."

    find("[data-trigger]").click
    click_button "Add a condition"
    find("button[role=combobox]", text: "What it reads").click
    find("[role=option]", text: "Instances after").click
    find("button[aria-label='How it compares']").click
    find("[role=option]", text: "is more than").click
    find("input[aria-label='Value']").fill_in(with: "20")
    take_screenshot
    using_wait_time(10) { assert_no_selector "[data-sonner-toast]" }
    click_button "Apply changes"

    assert_toast "The trigger was updated."
    trigger = @workflow.reload.draft.trigger
    assert_equal Workflow::Trigger::KIND_SERVICE_SCALED, trigger["kind"]
    assert_equal [ { "field" => "to", "operator" => PolicyRule::OPERATOR_GREATER_THAN, "value" => "20" } ], trigger["conditions"]
    assert_text "Only when 1 condition holds"
  end

  test "a number condition asks for a number, and the comparisons for words are not offered on one" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: workspace_memberships(:alice_workspace_one),
                    payload: { "trigger" => { "kind" => Workflow::Trigger::KIND_SERVICE_SCALED, "inputs" => [] } })
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    find("[data-trigger]").click
    click_button "Add a condition"
    find("button[role=combobox]", text: "What it reads").click
    find("[role=option]", text: "Instances before").click
    find("button[aria-label='How it compares']").click
    assert_selector "[role=option]", text: "is less than"
    assert_no_selector "[role=option]", text: "starts with"
    find("[role=option]", text: "is less than").click
    find("input[aria-label='Value']").fill_in(with: "a few")

    assert_text "Give each number condition a number, such as 20."
    assert_button "Apply changes", disabled: true
  end

  test "a number condition stored as a number opens with its number, and the trigger can still be changed" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: workspace_memberships(:alice_workspace_one),
                    payload: { "trigger" => { "kind" => Workflow::Trigger::KIND_SERVICE_SCALED, "inputs" => [],
                                              "conditions" => [ { "field" => "to", "operator" => PolicyRule::OPERATOR_GREATER_THAN, "value" => 20 } ] } })
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    find("[data-trigger]").click
    assert_equal "20", find("input[aria-label='Value']").value
    click_button "Add an input"
    find("input[placeholder='region']").fill_in(with: "region")
    find("input[aria-label='Question']").fill_in(with: "Which region?")
    click_button "Apply changes"

    assert_toast "The trigger was updated."
    assert_equal [ { "field" => "to", "operator" => PolicyRule::OPERATOR_GREATER_THAN, "value" => "20" } ], @workflow.reload.draft.trigger["conditions"]
  end

  test "an issue assigned trigger also starts on a label, set in its settings" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Issue assigned to Firefight" }
    assert_toast "The trigger was updated."

    find("[data-trigger]").click
    within("[data-trigger-settings]") do
      assert_text "Or when an issue gets this label"
      fill_in "trigger-label", with: "firefight"
    end
    take_screenshot
    using_wait_time(10) { assert_no_selector "[data-sonner-toast]" }
    click_button "Apply changes"

    assert_toast "The trigger was updated."
    assert_equal "firefight", @workflow.reload.draft.trigger[Workflow::Listening::KEY_LABEL]
  end

  test "a step offers what the trigger's data holds as a value to use" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, payload: { "trigger" => { "kind" => Workflow::Trigger::KIND_ALERT_RECEIVED, "inputs" => [] } },
                    by: workspace_memberships(:alice_workspace_one))
    @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: workspace_memberships(:alice_workspace_one),
                           payload: { "step" => { "id" => "tell", "name" => "tell", "kind" => "post_to_channel", "config" => { "channel" => "#ops", "message" => "" } } })
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    find("[data-step='tell']").click
    find("button[aria-label='Use an earlier value in message']").click

    assert_text "The alert's title"
    assert_text "What routing did"
  end
end
