require "application_system_test_case"

class CodeChangesTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @integration.integration_environments.create!(health_status: IntegrationEnvironment::HEALTH_HEALTHY)
    @integration.tools.create!(name: "fix_code", read_only: false, enabled: true, description: "Write a code change and open it as a pull request")
  end

  test "an admin lists the paths Halon may not change, sees why one cannot be read, and saves the list with a toast" do
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => @integration.id)

    within("[role='dialog']") do
      assert_text "Code changes"
      assert_text "Paths Halon may not change"
      assert_text "every change arrives for someone to review"
      assert_no_button "Save"
      page.save_screenshot(Rails.root.join("tmp/screenshots/code-changes-empty.png"))

      fill_in "Paths Halon may not change", with: ".github/workflows/\n../secrets"
      click_on "Save"
      assert_text "../secrets reaches outside the repository. Give a path inside it, such as infra/prod/"
      assert_field "Paths Halon may not change", with: ".github/workflows/\n../secrets"
      page.save_screenshot(Rails.root.join("tmp/screenshots/code-changes-refused.png"))

      fill_in "Paths Halon may not change", with: ".github/workflows/\ninfra/prod/**\n*.lock"
      click_on "Save"
    end

    assert_text "Saved. Halon may not change .github/workflows/, infra/prod/**, and *.lock in GitHub's repositories."
    within("[role='dialog']") do
      assert_field "Paths Halon may not change", with: ".github/workflows/\ninfra/prod/**\n*.lock"
      assert_no_button "Save"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/code-changes-saved.png"))
    assert_equal [ ".github/workflows/", "infra/prod/**", "*.lock" ], @integration.reload.protected_paths
  end
end
