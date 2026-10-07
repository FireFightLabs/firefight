require "application_system_test_case"

class GithubInstallationTest < ApplicationSystemTestCase
  PAGE = "https://github.com/organizations/acme/settings/installations/42".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = @integration.integration_environments.create!(health_status: IntegrationEnvironment::HEALTH_HEALTHY)
    @row.store_installation!("42")
    @row.installation_checked!(Integrations::Installations::Installation.new(account: "acme", page: PAGE, access: { "contents" => "read", "metadata" => "read" }))
    @integration.tools.create!(name: "fetch_file", read_only: true, enabled: true, description: "Read a file from the repository at a given commit")
    @integration.tools.create!(name: "workflow_runs", read_only: true, enabled: true, description: "List a repository's GitHub Actions workflow runs")
  end

  test "a switched-on tool lacking a permission says which, and disconnecting can remove the app from the account" do
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => @integration.id)

    within("[role='dialog']") do
      assert_text "1 switched-on tool needs a permission the GitHub App was not granted"
      assert_link "Review permissions on GitHub", href: PAGE
      assert_text "Needs Actions read in the GitHub App."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/github-needs-permission.png"))

    click_on "Disconnect"
    within("[role='dialog']", text: "Disconnect GitHub?") do
      assert_selector "button[role='checkbox'][data-state='checked']"
      assert_text "Also remove the Firefight app from acme on GitHub"
      page.save_screenshot(Rails.root.join("tmp/screenshots/github-disconnect-dialog.png"))
      find("button[role='checkbox']").click
      click_on "Disconnect"
    end

    assert_text "GitHub is disconnected. Firefight's app is still installed on acme."
    assert_button "Open acme on GitHub"
    page.save_screenshot(Rails.root.join("tmp/screenshots/github-disconnect-toast.png"))
    assert @integration.reload.deleted?
  end

  test "an installation another connection uses cannot be removed, and one removed on GitHub offers Reconnect" do
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub staging")
              .integration_environments.create!.store_installation!("42")
    other = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub old")
    other_row = other.integration_environments.create!
    other_row.store_installation!("7")
    other_row.installation_checked!(Integrations::Installations::Installation.new(state: Integrations::Installations::REMOVED, account: "acme-old"))

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => @integration.id)
    click_on "Disconnect"
    within("[role='dialog']", text: "Disconnect GitHub?") do
      assert_selector "button[role='checkbox'][data-state='unchecked'][disabled]"
      assert_text "GitHub staging also uses this installation, so the app stays on GitHub."
      page.save_screenshot(Rails.root.join("tmp/screenshots/github-disconnect-shared.png"))
      click_on "Cancel"
    end

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => other.id)
    within("[role='dialog']") do
      assert_text "Removed on GitHub"
      assert_text "Firefight's app was removed from acme-old on GitHub"
      assert_link "Reconnect"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/github-removed.png"))
  end
end
