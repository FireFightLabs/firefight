require "application_system_test_case"

class OncallConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "Opsgenie's credentials form asks for the key and which instance it belongs to" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => Integrations::Providers::Opsgenie.key)

    within("[role=dialog]") do
      assert_text "Connect Opsgenie"
      assert_text "API key"
      assert_text "not restricted to access configurations"
      find("#connect-region").click
    end
    find("[role=option]", text: "EU (app.eu.opsgenie.com)").click
    within("[role=dialog]") { assert_text "EU (app.eu.opsgenie.com)" }
    page.save_screenshot(Rails.root.join("tmp/screenshots/opsgenie-connect.png"))
  end

  test "PagerDuty asks which service region on one-click connect" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => Integrations::Providers::Pagerduty.key)

    within("[role=dialog]") do
      assert_text "US (app.pagerduty.com)"
      find("button[role=combobox]", text: "US (app.pagerduty.com)").click
    end
    find("[role=option]", text: "EU (app.eu.pagerduty.com)").click
    within("[role=dialog]") { assert_includes find_link("Continue with PagerDuty")[:href], "region=eu" }
    page.save_screenshot(Rails.root.join("tmp/screenshots/pagerduty-connect.png"))
  end
end
