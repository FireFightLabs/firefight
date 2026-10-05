require "application_system_test_case"

class GitlabConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "GitLab connects with an access token and an optional address, and its own MCP server is one click away" do
    Integrations::GitlabApi.any_instance.stubs(:get).raises(Integrations::GitlabApi::Refused, "GitLab answered 401: 401 Unauthorized")

    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "gitlab")

    within("[role=dialog]") do
      assert_text "Enter credentials for each environment."
      assert_field "GitLab address (optional)", placeholder: "https://gitlab.com"
      assert_button "Connect", disabled: true
      fill_in "Access token", with: "glpat-wrong"
      click_button "Connect"
      assert_text "GitLab refused this token: GitLab answered 401: 401 Unauthorized. Check it is active and has the read_api scope."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/gitlab-connect.png"))

    within("[role=dialog]") do
      click_button "Use an MCP server instead"
      assert_link "Continue with GitLab", href: /kind=mcp/
      click_button "Back to credentials"
      assert_field "Access token"
    end
    assert_equal 0, @workspace.integrations.where(provider: "gitlab").count
  end

  test "CircleCI sits in the CI group and connects with one click to its hosted server" do
    visit integrations_path

    within(:xpath, "//section[.//h3[text()='CI']]") { assert_text "CircleCI" }
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "circleci")
    within("[role=dialog]") do
      assert_link "Continue with CircleCI"
      assert_no_text "kind=mcp"
    end
  end
end
