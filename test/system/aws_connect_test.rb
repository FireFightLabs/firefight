require "application_system_test_case"

class AwsConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "AWS is connected with an access key and the regions chosen from AWS's list, and AWS is asked about the key in the first" do
    Integrations::AwsApi.any_instance.expects(:identity).with("eu-west-1").at_least_once.returns(account: "123456789012")
    Integrations::AwsApi.any_instance.stubs(:all).returns([ [], false ])
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "aws")

    within("[role=dialog]") do
      fill_in "Access key ID", with: "AKIAEXAMPLE"
      fill_in "Secret access key", with: "secret"
      assert_text "The regions this environment runs in."
      click_button "Choose regions"
    end
    find("[role=option]", text: "Europe (Ireland)").click
    find("[role=option]", text: "US East (N. Virginia)").click
    find("body").send_keys(:escape)
    page.save_screenshot(Rails.root.join("tmp/screenshots/aws-connect.png"))

    within("[role=dialog]") { click_button "Connect" }

    assert_no_selector "[role=dialog]"
    row = @workspace.integrations.find_by!(provider: "aws").integration_environments.sole
    assert_equal %w[eu-west-1 us-east-1], Integrations::ConnectionSettings.of(row).field("regions")
    assert_equal "AKIAEXAMPLE", Integrations::ConnectionSettings.of(row).credential("access_key_id")
  end
end
