require "application_system_test_case"

class CloudConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "Azure asks which cloud, its secret as a credential, the tenant and client as fields, and lists the subscriptions to choose from" do
    Integrations::AzureApi.any_instance.stubs(:subscriptions).returns(Integrations::Pages::Read.new(items: [
      { "subscriptionId" => "11111111-2222-3333-4444-555555555555", "displayName" => "Production", "state" => "Enabled" },
      { "subscriptionId" => "99999999-2222-3333-4444-555555555555", "displayName" => "Staging", "state" => "Enabled" }
    ], complete: true))
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "azure")

    within("[role=dialog]") do
      assert_field "Client secret", type: "password"
      assert_field "Tenant"
      assert_field "Client ID"
      find("#connect-region").click
    end
    find("[role=option]", text: "US Government (portal.azure.us)").click
    within("[role=dialog]") do
      fill_in "Client secret", with: "s3cret"
      fill_in "Tenant", with: "contoso.onmicrosoft.us"
      fill_in "Client ID", with: "22222222-2222-3333-4444-555555555555"
      click_button "Choose subscriptions"
    end
    assert_selector "[role=option]", text: IntegrationProvider::ConnectField::ALL_LABEL
    find("[role=option]", text: "Production").click
    find("[role=option]", text: "Staging").click
    page.save_screenshot(Rails.root.join("tmp/screenshots/azure-connect-subscriptions.png"))
    find("[cmdk-input]").set("prod-typed")
    find("[role=option]", text: "Add").click
    find("body").send_keys(:escape)
    within("[role=dialog]") do
      click_button "Connect"
      assert_text "Subscriptions can hold only a GUID such as 00000000-0000-0000-0000-000000000000, and prod-typed does not."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/azure-connect.png"))
  end

  test "Google Cloud asks for its key as a credential and its projects as a field" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "google_cloud")

    within("[role=dialog]") do
      assert_selector "textarea#connect-service_account_key"
      assert_button "Choose projects"
      assert_no_text "Region"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/google-cloud-connect.png"))
  end
end
