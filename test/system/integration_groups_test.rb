require "application_system_test_case"

class IntegrationGroupsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "providers sit in the groups in the registry's order, and a card's info button says what it is and what Halon can do with it" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)

    visit integrations_path

    headings = all("section h3").map(&:text)
    assert_equal IntegrationProvider.categories.keys, headings.select { |heading| IntegrationProvider.categories.key?(heading) }
    find("button[aria-label='About Northflank']").click
    within("[role='dialog']") do
      assert_text "Cloud and hosting"
      assert_text "Halon can read its logs"
      assert_text "roll a resource back, restart a service, and scale a service"
      assert_text "What Northflank holds is kept current on the map"
    end
    find("body").send_keys(:escape)

    find("button[aria-label='About Datadog']").click
    within("[role='dialog']") do
      assert_text "for the services on the map that Datadog watches"
      assert_no_text "On the map"
    end
  end

  test "without Halon a provider's details say nothing about it" do
    visit integrations_path

    find("button[aria-label='About Northflank']").click
    within("[role='dialog']") { assert_no_text "With Halon" }
  end
end
