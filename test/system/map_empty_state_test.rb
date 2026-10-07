require "application_system_test_case"

class MapEmptyStateTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "an empty map names the kinds of provider that fill it and links to Integrations" do
    visit resource_map_path

    assert_text "Nothing is on the map yet"
    assert_text "Connect a cloud, hosting or database provider and what it runs appears here"
    assert_no_text "Northflank or PlanetScale"
    page.save_screenshot(Rails.root.join("tmp/screenshots/map-empty-state.png"))

    click_on "Connect a provider"
    assert_current_path integrations_path
  end
end
