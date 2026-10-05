require "application_system_test_case"

class CloudConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "Azure asks which cloud, its secret as a credential, and the tenant, client and subscription as fields with their format" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "azure")

    within("[role=dialog]") do
      assert_field "Client secret", type: "password"
      assert_field "Tenant"
      assert_field "Client ID"
      assert_field "Subscription ID"
      find("#connect-region").click
    end
    find("[role=option]", text: "US Government (portal.azure.us)").click
    within("[role=dialog]") do
      fill_in "Client secret", with: "s3cret"
      fill_in "Tenant", with: "contoso.onmicrosoft.us"
      fill_in "Client ID", with: "22222222-2222-3333-4444-555555555555"
      fill_in "Subscription ID", with: "prod"
      click_button "Connect"
      assert_text "Subscription ID can hold only a GUID"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/azure-connect.png"))
  end

  test "Google Cloud asks for its key as a credential and its project as a field" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "google_cloud")

    within("[role=dialog]") do
      assert_selector "textarea#connect-service_account_key"
      assert_field "Project"
      assert_no_text "Region"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/google-cloud-connect.png"))
  end
end
