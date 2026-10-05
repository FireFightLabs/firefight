require "application_system_test_case"

class ProductAnalyticsConnectTest < ApplicationSystemTestCase
  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "PostHog asks for US or EU and Mixpanel for US, EU or India, each sending one-click connect to that region" do
    { "posthog" => [ "PostHog", "EU (eu.posthog.com)", "eu" ], "mixpanel" => [ "Mixpanel", "India (in.mixpanel.com)", "in" ] }.each do |key, (name, label, region)|
      visit integrations_path(Integration::CONNECT_QUERY_PARAM => key)

      within("[role=dialog]") do
        assert_text "Where your #{name} account is"
        find("button[role=combobox]", text: IntegrationProvider.find(key).regions.first.label).click
      end
      find("[role=option]", text: label).click
      within("[role=dialog]") { assert_includes find_link("Continue with #{name}")[:href], "region=#{region}" }
      page.save_screenshot(Rails.root.join("tmp/screenshots/#{key}-connect.png"))
    end
  end
end
