require "application_system_test_case"

# A runbook Halon can run is edited with a picker of the tools Halon can use and a form made from the chosen tool's
# parameters, and a watch made of what to follow, never JSON. One Halon saved comes back out exactly as it went in.
class RunbookProcedureEditorTest < ApplicationSystemTestCase
  WATCH = {
    "title" => "release", "minutes" => 90, "expected_minutes" => 20,
    "steps" => [ { "label" => "Release run", "capability" => "run_history", "resource" => "firefight", "name" => "{{bump}}", "report_start" => true, "connection" => "github" } ]
  }.freeze
  ARGUMENTS = { "query" => "release {{bump}}", "limit" => 5, "filters" => { "kept" => [ 1, 2 ] } }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    row = github.integration_environments.create!(credentials: { token: "x" }.to_json)
    github.tools.create!(name: "ci_runs", description: "CI runs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/firefight",
                                  name: "firefight", integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
    @runbook = @workspace.runbooks.create!(name: "Release Firefight", aliases: [ "ship it" ],
                                           inputs: [ { "key" => "bump", "question" => "Which version bump?", "default" => "patch" } ], watch: WATCH)
    @runbook.sync_steps!([ { title: "Look for past releases", tool: "search_incidents", arguments: ARGUMENTS } ])
    sign_in(users(:alice), @workspace)
  end

  test "a runbook Halon saved round trips through the editor unchanged" do
    open_editor

    assert_text "search_incidents"
    assert_field "step-#{@runbook.runbook_steps.sole.id}-query", with: "release {{bump}}"
    assert_text "filters:"
    assert_equal "Release run", find("input[aria-label='Watch 1 label']").value
    assert_field "runbook-watch-minutes", with: "90"
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-editor-saved.png"))

    fill_in "runbook-summary", with: "Ship a release"
    click_button "Save changes"
    assert_text "Release Firefight was updated."

    @runbook.reload
    assert_equal "Ship a release", @runbook.summary
    assert_equal ARGUMENTS, @runbook.runbook_steps.sole.arguments
    assert_equal WATCH, @runbook.watch
    assert_equal [ "ship it" ], @runbook.aliases
  end

  test "a step's tool is picked from the tools grouped as a person finds them, its fields are made from its parameters, and a required one left empty says so in place" do
    open_editor
    click_button "Add step"
    all("button[role='combobox']", text: "None, a person does this step").last.click
    find("[cmdk-input]").fill_in(with: "run_history")
    assert_text "Anything on the resource map"
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-editor-tool-picker.png"))
    find("[cmdk-item]", text: "run_history").click

    assert_selector "label", text: /\Aresource\s*\*/
    assert_text "Recent runs of one resource on the map"
    click_button "Save changes"
    assert_text "Required."
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-editor-required.png"))
    assert_equal 1, @runbook.reload.runbook_steps.count
  end

  test "the watch is made of what to follow and what counts as done, with a learned time limit by default" do
    @runbook.update!(watch: nil)
    open_editor
    find("#runbook-watch-on").click
    fill_in "runbook-watch-title", with: "release"
    find("input[aria-label='Watch 1 label']").fill_in(with: "Release run")
    find("button[role='combobox']", text: /How to check it|Run history/).click
    find("[cmdk-item]", text: "Run history").click
    find("button[role='combobox']", text: "On which resource").click
    find("[cmdk-item]", text: "firefight").click
    find("input[aria-label='Watch 1 run name']").fill_in(with: "release")
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-editor-watch.png"))
    click_button "Save changes"
    assert_text "Release Firefight was updated."

    assert_equal({ "title" => "release", "steps" => [ { "capability" => "run_history", "label" => "Release run", "resource" => "firefight", "name" => "release" } ] },
                 @runbook.reload.watch)
  end

  private

  # The tools' fields arrive once the editor asks for them, which the step's own description shows.
  def open_editor
    visit settings_runbooks_path
    within(:xpath, "//tr[.//*[text()='Release Firefight']]") { click_button "Actions" }
    find("[role='menuitem']", text: "Edit").click
    assert_text "Edit runbook"
    assert_text "Search this workspace's incidents"
  end
end
