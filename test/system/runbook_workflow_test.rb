require "application_system_test_case"

# A runbook is a guide. Its editor links the workflow Run it starts instead of building
# steps that run, its page shows that workflow with Run it, and so does an incident it is attached to.
class RunbookWorkflowTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    @runbook = @workspace.runbooks.create!(name: "Release Firefight", summary: "Ships a release", aliases: [ "ship it" ],
                                           inputs: [ { "key" => "bump", "question" => "Which version bump?", "default" => "patch" } ])
    @runbook.sync_steps!([ { title: "Look for past releases", instruction: "So the bump matches.", tool: "search_incidents", arguments: { "query" => "{{bump}}" } },
                           { title: "Tell the team" } ])
    @workflow = @runbook.reload.move_runnable_parts!
    sign_in(users(:alice), @workspace)
  end

  test "the editor links a workflow, opens it on its page, and shows the steps as a checklist only" do
    rollback = Workflow.create!(workspace: @workspace, name: "Roll back web")
    visit settings_runbooks_path
    within(:xpath, "//tr[.//*[text()='Release Firefight']]") { click_button "Actions" }
    find("[role='menuitem']", text: "Edit").click

    assert_text "Edit runbook"
    assert_text "Run it on this runbook starts the workflow you link here"
    assert_no_text "Tool Halon runs it with"
    assert_no_text "Run by Halon"
    assert_link "Open Release Firefight on its page", href: workflow_path(@workflow)
    assert_field "runbook-aliases", with: "ship it"
    scroll_to find("#runbook-workflow")
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-workflow-editor.png"))

    find("#runbook-workflow").click
    find("[cmdk-item]", text: "Roll back web").click
    click_button "Save changes"

    assert_text "Release Firefight was updated."
    assert_equal rollback, @runbook.reload.workflow
    assert_equal [ "Look for past releases", "Tell the team" ], @runbook.runbook_steps.map(&:title)
  end

  test "the runbook's page shows its workflow, and Run it asks the run's questions and starts it" do
    WorkflowPublishService.new(@workflow).publish!(@workflow.draft, by: @admin)
    visit settings_runbooks_path(Runbook::QUERY_PARAM => @runbook.id)

    assert_text "WORKFLOW"
    assert_text "Live"
    assert_link "Open the workflow", href: workflow_path(@workflow)
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-workflow-sheet.png"))

    click_button "Run it"
    assert_text "Run Release Firefight"
    assert_field "runbook-run-input-bump", with: "patch"
    fill_in "runbook-run-input-bump", with: "minor"
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-workflow-run-dialog.png"))
    click_button "Run"

    assert_text "Release Firefight is running."
    assert_text "Follow its run"
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-workflow-running.png"))
    assert_equal({ "bump" => "minor" }, @workflow.runs.sole.inputs)
  end

  test "a draft nobody published says why Run it cannot be pressed" do
    visit settings_runbooks_path(Runbook::QUERY_PARAM => @runbook.id)

    assert_text "Draft"
    assert_button "Run it", disabled: true
    find("button", text: "Run it").find(:xpath, "..").hover
    assert_text "Release Firefight has no published version to run."
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-workflow-draft.png"))
  end

  test "an incident the runbook is attached to offers Run it, which names the incident on the run" do
    WorkflowPublishService.new(@workflow).publish!(@workflow.draft, by: @admin)
    incident = incidents(:active_critical_ws1)
    incident.incident_runbooks.create!(runbook: @runbook, workspace: @workspace)

    visit incident_path(incident)
    assert_text "Release Firefight"
    scroll_to find("button", text: "Run it")
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-workflow-incident.png"))
    click_button "Run it"
    assert_text "Run Release Firefight"
    click_button "Run"

    assert_text "Release Firefight is running."
    assert_equal incident.identifier, @workflow.runs.sole.trigger_payload.dig("incident", "identifier")
  end
end
