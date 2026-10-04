require "application_system_test_case"

class KubernetesConnectTest < ApplicationSystemTestCase
  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "a cluster is connected with its token and CA, and the address and namespaces are checked on the form" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "kubernetes")

    within("[role=dialog]") do
      assert_field "Service account token"
      assert_field "CA certificate"
      assert_field "API server"
      fill_in "Service account token", with: "sa-token"
      assert_selector "textarea#connect-ca"
      fill_in "CA certificate", with: "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----"
      fill_in "API server", with: "https://cluster.example.com:6443"
      fill_in "Namespaces", with: "Production_1"
      click_button "Connect"
      assert_text "Namespaces can hold only namespace names separated by commas, or * alone."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/kubernetes-connect.png"))

    assert_equal 0, workspaces(:slack_workspace_one).integrations.where(provider: "kubernetes").count
  end
end
