require "application_system_test_case"

# An admin decides on Settings, Workspace whether Halon makes safe changes without asking, and keeps the list of risky
# changes it may make without asking. Every change to either says so in a toast.
class ChangesWithoutAskingTest < ApplicationSystemTestCase
  PHONE = [ 390, 844 ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.integration_environments.create!(credentials: { token: "x" }.to_json)
    @merge = github.tools.create!(name: "merge_pull_request", description: "Merge", enabled: true, read_only: false, params_schema: {})
    github.tools.create!(name: "set_actions_secret", description: "Set a secret", enabled: true, read_only: false, params_schema: {})
    sign_in(users(:alice), @workspace)
  end

  test "an admin turns safe changes off, then adds, turns off and deletes an entry of the list, each with a toast" do
    visit settings_workspace_path

    switch = find("#safe-changes")
    execute_script("arguments[0].scrollIntoView({ block: 'center' })", switch)
    shot("without-asking-setting")
    switch.click
    click_button "Save changes"
    assert_toast "Halon now asks before safe changes."
    assert_not @workspace.reload.safe_changes_without_asking?

    card = find("h3, div", text: "Halon may do these without asking", match: :first)
    execute_script("arguments[0].scrollIntoView({ block: 'start' })", card)
    assert_text "Nothing yet. Every risky change asks the person in the chat"
    shot("without-asking-empty")

    click_button "Add"
    find("#allowance-change").click
    assert_no_selector "[role=option]", text: "Set actions secret on GitHub"
    find("[role=option]", text: "Merge pull request on GitHub").click
    find("#allowance-environment").click
    find("[role=option]", text: "Production").click
    shot("without-asking-dialog")
    within("[role=dialog]") { click_button "Add" }

    assert_toast "\"Merge pull request on GitHub in Production\" was added to what Halon may do without asking."
    assert_text "Merge pull request on GitHub in Production"
    assert_text "Not yet"
    entry = @workspace.allowances.sole
    assert_equal [ @merge.ability_action, catalog_entries(:production_env) ], [ entry.action, entry.environment ]
    execute_script("arguments[0].scrollIntoView({ block: 'center' })", find("tr", text: "Merge pull request on GitHub in Production"))
    shot("without-asking-list")

    within("tr", text: "Merge pull request on GitHub in Production") { find("[role=switch]").click }
    assert_toast "\"Merge pull request on GitHub in Production\" is off."
    assert_not entry.reload.enabled?

    within("tr", text: "Merge pull request on GitHub in Production") { find("button[aria-haspopup=menu]").click }
    find("[role=menuitem]", text: "Delete").click
    assert_text "comes off the list, and Halon asks the person before it again."
    within("[role=dialog]") { click_button "Delete" }
    assert_toast "\"Merge pull request on GitHub in Production\" was deleted."
    assert_equal 0, @workspace.allowances.count

    page.current_window.resize_to(*PHONE)
    execute_script("arguments[0].scrollIntoView({ block: 'center' })", find("#safe-changes"))
    shot("without-asking-phone")
    @workspace.allowances.create!(capability: Integrations::Capabilities::ROLLBACK, environment: catalog_entries(:production_env))
    visit settings_workspace_path
    execute_script("arguments[0].scrollIntoView({ block: 'center' })", find("tr", text: "Roll back deploys in Production"))
    shot("without-asking-list-phone")
  end

  private

  def shot(name) = page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png"))
end
