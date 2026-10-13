require "application_system_test_case"

class HalonWorkflowLibraryTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:available_for?).returns(true)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
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

    visit halon_workflow_library_path
    assert_text "No workflows yet"
    click_button "Use"
    assert_text "Use it as it is"
    click_button "Make the draft"

    assert_toast "Cool down was made from Firefight's library and moves with its new versions. Publish its draft to run it."
    assert_text "Firefight's Cool down, version 1, kept up to date"
    assert_text "Draft only, not published yet"
  end

  test "an item this workspace cannot run stays listed with why, and one it can is used" do
    unrunnable = item.with(key: "scan_it", name: "Scan it",
                           definition: item.definition.merge("steps" => [ { "id" => "step_x", "name" => "scan", "kind" => "run_skill", "config" => { "skill" => "no_such_skill" } } ]))
    Workflow::Library.stubs(:all).returns([ unrunnable, item ])

    visit halon_workflow_library_path

    assert_text "Scan it"
    assert_selector "button[disabled]", text: "Use", count: 1
  end

  test "a copy sees what Firefight changed and takes it into a draft" do
    Workflow::Library.stubs(:all).returns([ item ])
    copy = Workflow.from_library!(item, workspace: @workspace, by: @alice, following: false)
    copy.draft.publish!(by: @alice)
    Workflow::Library.stubs(:all).returns([ item(version: 2, minutes: 10) ])

    visit halon_workflow_library_path
    click_button "Version 2 is out"
    assert_text "Changed its settings of the step wait."
    click_button "Take it into a draft"

    assert_toast "Cool down has a new draft, version 2, holding Firefight's version 2. Publish it to run it."
  end

  test "a workflow file is imported as a draft" do
    Workflow::Library.stubs(:all).returns([ item ])
    source = Workflow.from_library!(item, workspace: workspaces(:slack_workspace_two), by: workspace_memberships(:alice_workspace_two))
    path = Rails.root.join("tmp", "cool_down#{Workflow::Document::EXTENSION}")
    File.write(path, Workflow::Document.render(source))

    visit halon_workflow_library_path
    click_button "Import a workflow"
    attach_file "File", path
    click_button "Import"

    assert_toast "Cool down was imported as a draft. Publish it to run it."
    assert_text "Your own"
  ensure
    FileUtils.rm_f(path) if path
  end
end
