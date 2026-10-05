require "application_system_test_case"

class CodingAgentChoiceTest < ApplicationSystemTestCase
  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "a coding agent is connected with its key, then chosen to write code fixes, and the page says what it still needs" do
    Integrations::DevinApi.any_instance.stubs(:whoami).returns("principal_type" => "service_user", "org_id" => "org-abc")
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "devin")

    within("[role=dialog]") do
      fill_in "API key", with: "cog_key"
      fill_in "Organization ID", with: "org-abc"
      page.save_screenshot(Rails.root.join("tmp/screenshots/coding-agent-devin-form.png"))
      click_button "Connect"
    end
    assert_no_selector "[role=dialog]"
    assert_text "Coding agents"
    row = workspaces(:slack_workspace_one).integrations.find_by!(provider: "devin").integration_environments.sole
    assert_equal({ "organization" => "org-abc" }, row.fields)
    page.save_screenshot(Rails.root.join("tmp/screenshots/coding-agent-connected.png"))

    visit settings_workspace_path
    find("#code-fix-agent").click
    find("[role=option]", text: "Devin").click
    click_button "Save changes"

    assert_text "Workspace settings were updated."
    assert_text "Devin's fix_code tool is switched off, so code steps wait for a person. Switch it on under Integrations."
    assert_equal "devin", workspaces(:slack_workspace_one).reload.code_fix_agent
    page.save_screenshot(Rails.root.join("tmp/screenshots/coding-agent-chosen.png"))
  end

  test "Factory's connect form asks which of its deployments the organization is on" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "factory")

    within("[role=dialog]") do
      assert_text "Global (app.factory.ai)"
      assert_field "Droid Computer"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/coding-agent-factory-region.png"))
  end

  test "with no coding agent connected, Firefight's own agent is the only choice and the page says where to connect one" do
    visit settings_workspace_path

    assert_text "Write code fixes with"
    assert_text "Firefight's own agent"
    assert_text "No coding agent is connected yet. Connect one under Integrations to choose it here."
    page.save_screenshot(Rails.root.join("tmp/screenshots/coding-agent-none.png"))
  end
end
