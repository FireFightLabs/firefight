require "application_system_test_case"

class TokenFieldsConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    Integrations::ConnectionRefresh.stubs(:run!).returns(true)
  end

  test "ClickHouse's token form asks its key's id and secret, and Firefight builds the header" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "clickhouse")

    within("[role=dialog]") do
      click_button "Use a token instead"
      assert_no_field "Access key (sent as the Authorization header)"
      fill_in "Key ID", with: "id-1"
      fill_in "Key secret", with: "s3cret"
      assert_equal "password", find_field("Key secret")[:type]
      page.save_screenshot(Rails.root.join("tmp/screenshots/clickhouse-token-fields.png"))
      click_button "Connect & discover tools"
    end

    assert_toast "ClickHouse is connected."
    assert_no_selector "[role=dialog]"
    row = @workspace.integrations.find_by!(provider: "clickhouse").integration_environments.sole
    assert_equal "Basic #{Base64.strict_encode64('id-1:s3cret')}", Integrations::Credentials.headers_for(row)["Authorization"]
  end

  test "Upstash's token form asks the account's email and a Developer API key" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "upstash")

    within("[role=dialog]") do
      click_button "Use a token instead"
      assert_button "Connect & discover tools", disabled: true
      fill_in "Email", with: "ops@example.com"
      fill_in "API key", with: "k3y"
      page.save_screenshot(Rails.root.join("tmp/screenshots/upstash-token-fields.png"))
      click_button "Connect & discover tools"
    end

    assert_toast "Upstash is connected."
    assert_no_selector "[role=dialog]"
    row = @workspace.integrations.find_by!(provider: "upstash").integration_environments.sole
    assert_equal "Bearer ops@example.com:k3y", Integrations::Credentials.headers_for(row)["Authorization"]
  end
end
