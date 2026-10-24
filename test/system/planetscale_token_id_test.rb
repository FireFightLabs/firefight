require "application_system_test_case"

class PlanetscaleTokenIdTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "the token form asks for a PlanetScale service token's id beside its secret" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "planetscale")

    within("[role=dialog]") do
      click_button "Use a token instead"
      assert_field "Service token ID"
      assert_text "Leave it empty when you sign in."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/planetscale-token-form.png"))
  end

  test "a connection made without the id gets it from its details, in a dialog, and says so in a toast" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    row = integration.integration_environments.create!(credentials: IntegrationEnvironment.token_credentials("Bearer pscale_tkn_secret"))
    Integrations::ConnectionRefresh.stubs(:run!).returns(true)

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => integration.id)
    assert_text "Service token ID"
    assert_text "Not set"
    page.save_screenshot(Rails.root.join("tmp/screenshots/planetscale-token-id-details.png"))

    click_button "Add", exact: true
    within(find("[role=dialog]", text: "Add service token ID")) do
      fill_in "Service token ID", with: "tok123"
      page.save_screenshot(Rails.root.join("tmp/screenshots/planetscale-token-id-dialog.png"))
      click_button "Save"
    end

    assert_toast "PlanetScale's service token ID was saved."
    assert_button "Change"
    assert_no_text "pscale_tkn_secret"
    assert_equal "tok123", row.reload.fields["service_token_id"]
    page.save_screenshot(Rails.root.join("tmp/screenshots/planetscale-token-id-saved.png"))
  end
end
