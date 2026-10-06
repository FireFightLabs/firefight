require "application_system_test_case"

class MapSearchTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    build_two_environment_map(@workspace)
    SearchDocument.index!(ResourceMap::Resource, ResourceMap::Resource.where(workspace: @workspace).pluck(:id))
    SearchDocument.index!(CatalogEntry, @workspace.catalog_entries.pluck(:id))
    sign_in(users(:alice), @workspace)
  end

  test "the shortcut opens search anywhere, and a resource opens the map focused on it" do
    visit root_path
    find("body").send_keys([ :control, "k" ])

    within("[role=dialog]") do
      find("input").send_keys("orders")
      assert_text "orders-db"
      assert_text "Database · Northflank · acme/shop · Production"
      assert_text "Matches its name."
      edges = evaluate_script("(() => { const style = getComputedStyle(document.activeElement); return [style.outlineStyle, style.borderTopWidth, style.boxShadow] })()")
      assert_equal [ "none", "0px", "none" ], edges
      page.save_screenshot(Rails.root.join("tmp/screenshots/map-search-palette.png"))
      find("input").send_keys(:enter)
    end

    assert_current_path(/\/app\/map\?resource=#{map_resource(@workspace, "orders-db").id}&view=focus/)
    assert_selector "aside[aria-label='About orders-db']"
    page.save_screenshot(Rails.root.join("tmp/screenshots/map-search-focus.png"))

    find("button[aria-label='Search the map, catalog and memory']").click
    within("[role=dialog]") do
      find("input").send_keys("web")
      assert_text "Exactly its name."
      find("input").send_keys(:enter)
    end
    assert_current_path(/resource=#{map_resource(@workspace, "web").id}/)
    assert_selector "aside[aria-label='About web']"
  end

  test "a catalog entry opens in its catalog type, and a confirmed memory is marked on the Memory page" do
    Chat::Memory.create!(workspace: @workspace, subject: catalog_entries(:auth_service), text: "Authentication tokens live for an hour",
                         state: Chat::Memory::STATE_CONFIRMED, confirmed_by: workspace_memberships(:alice_workspace_one))
    visit settings_members_path

    find("button[aria-label='Search the map, catalog and memory']").click
    within("[role=dialog]") do
      find("input").send_keys("authentication")
      assert_text "Service in the catalog"
      assert_text "Confirmed memory about Auth Service"
      find("[cmdk-item]", text: "Service in the catalog").click
    end

    assert_current_path(/\/app\/catalogue\/service\?entry=/)
    within("[role=dialog]") { assert_text "Auth Service" }
    page.save_screenshot(Rails.root.join("tmp/screenshots/map-search-catalog-entry.png"))
    find("body").send_keys(:escape)
    assert_no_selector "[role=dialog]"

    find("button[aria-label='Search the map, catalog and memory']").click
    within("[role=dialog]") do
      find("input").send_keys("tokens")
      find("[cmdk-item]", text: "Authentication tokens live for an hour").click
    end

    assert_current_path(/\/app\/memory\?memory=/)
    assert_selector "tr[data-focused]", text: "Authentication tokens live for an hour"
    page.save_screenshot(Rails.root.join("tmp/screenshots/map-search-memory.png"))
  end

  test "a member who reads no part of the map is told why in the search" do
    member = workspace_memberships(:bob_workspace_one)
    grant = limit_map_to(@workspace, member, catalog_entries(:production_env))
    grant.update_column(:expires_at, 1.minute.ago)
    sign_in(users(:bob), @workspace)
    visit root_path

    find("button[aria-label='Search the map, catalog and memory']").click
    within("[role=dialog]") do
      find("input").send_keys("web")
      assert_text MapSearchController::NO_MAP_REACH
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/map-search-no-reach.png"))
  end
end
