require "application_system_test_case"

class HalonWorkflowLibraryTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:available_for?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  def item(version: 1, minutes: 5)
    Workflow::Library::Item.new(
      key: "cool_down", name: "Cool down", description: "Waits a while before carrying on.", aliases: [], version: version,
      definition: { "trigger" => { "kind" => Workflow::Trigger::KIND_MANUAL, "inputs" => [] },
                    "steps" => [ { "id" => "step_wait", "name" => "wait", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => minutes } } ],
                    "edges" => [], "outputs" => {} }
    )
  end

  test "a library workflow is used as it is from its dialog, says so, and is listed as kept up to date" do
    Workflow::Library.stubs(:all).returns([ item ])

    visit halon_workflows_path(tab: WorkflowsController::TAB_LIBRARY)
    assert_text "No workflows yet"
    click_button "Use"
    assert_text "Use it as it is"
    click_button "Make the draft"

    assert_toast "Cool down was made from Firefight's library and moves with its new versions. Publish its draft to run it."
    assert_text "Firefight's Cool down, version 1, kept up to date"
    assert_text "Draft only, not published yet"
  end

  test "the library is a tab of the Workflows page, its old address opens it, and a scheduled check asks what to check before it is made" do
    visit halon_workflow_library_path
    assert_selector "[role=tab][aria-selected=true]", text: "Library"
    assert_no_link "Workflow library"
    page.save_screenshot(Rails.root.join("tmp/screenshots/workflows-library-tab.png").to_s)

    within(:xpath, "//tr[.//*[text()='Scheduled check']]") { click_button "Use" }
    assert_text "What should Halon check?"
    assert_selector "textarea[aria-required=true]", count: 1
    click_button "Make the draft"
    assert_text "Answer this to use it."
    page.save_screenshot(Rails.root.join("tmp/screenshots/workflows-library-question.png").to_s)

    fill_in "What should Halon check?", with: "The orders queue should never pass 1000."
    click_button "Make the draft"
    assert_toast "Scheduled check was made from Firefight's library and moves with its new versions. Publish its draft to run it."
    page.driver.browser.manage.window.resize_to(390, 900)
    page.save_screenshot(Rails.root.join("tmp/screenshots/workflows-library-tab-phone.png").to_s)
  end

  test "an item this workspace cannot run stays listed with why, and one it can is used" do
    unrunnable = item.with(key: "scan_it", name: "Scan it",
                           definition: item.definition.merge("steps" => [ { "id" => "step_x", "name" => "scan", "kind" => "run_skill", "config" => { "skill" => "no_such_skill" } } ]))
    Workflow::Library.stubs(:all).returns([ unrunnable, item ])

    visit halon_workflows_path(tab: WorkflowsController::TAB_LIBRARY)

    assert_text "Scan it"
    assert_selector "button[disabled]", text: "Use", count: 1
  end

  test "a copy sees what Firefight changed and takes it into a draft" do
    Workflow::Library.stubs(:all).returns([ item ])
    copy = Workflow.from_library!(item, workspace: @workspace, by: @alice, following: false)
    copy.draft.publish!(by: @alice)
    Workflow::Library.stubs(:all).returns([ item(version: 2, minutes: 10) ])

    visit halon_workflows_path(tab: WorkflowsController::TAB_LIBRARY)
    click_button "Version 2 is out"
    assert_text "Changed its settings of the step wait."
    click_button "Take it into a draft"

    assert_toast "Cool down has a new draft, version 2, holding Firefight's version 2. Publish it to run it."
  end

  test "a member uses a library workflow and imports a file, which making workflows allows, and does not take Firefight's changes" do
    Workflow::Library.stubs(:all).returns([ item ])
    copy = Workflow.from_library!(item, workspace: @workspace, by: @alice, following: false)
    copy.draft.publish!(by: @alice)
    Workflow::Library.stubs(:all).returns([ item(version: 2, minutes: 10) ])
    sign_in(users(:bob), @workspace)

    visit halon_workflows_path(tab: WorkflowsController::TAB_LIBRARY)

    assert_button "Use"
    assert_button "Import a workflow"
    click_button "Version 2 is out"
    assert_text "Changed its settings of the step wait."
    assert_no_button "Take it into a draft"
  end

  test "a workflow file is imported as a draft" do
    Workflow::Library.stubs(:all).returns([ item ])
    source = Workflow.from_library!(item, workspace: workspaces(:slack_workspace_two), by: workspace_memberships(:alice_workspace_two))
    path = Rails.root.join("tmp", "cool_down#{Workflow::Document::EXTENSION}")
    File.write(path, Workflow::Document.render(source))

    visit halon_workflows_path(tab: WorkflowsController::TAB_LIBRARY)
    click_button "Import a workflow"
    attach_file "File", path
    click_button "Import"

    assert_toast "Cool down was imported as a draft. Publish it to run it."
    assert_text "Your own"
  ensure
    FileUtils.rm_f(path) if path
  end
end
