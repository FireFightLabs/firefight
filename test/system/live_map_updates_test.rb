require "application_system_test_case"

class LiveMapUpdatesTest < ApplicationSystemTestCase
  include LiveUpdatesTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    # Northflank sends no changes yet, so the test gives it the test provider's, set up by hand.
    Integrations::Providers::Northflank.stubs(:map_events).returns(LiveTestEvents)
    @row = connect_live!(@workspace, provider: "northflank", name: "Northflank")
    @row.give_map_events_token!
    @previous_host = ENV["APP_HOST"]
    ENV["APP_HOST"] = "firefight.example.com"
  end

  teardown do
    ENV["APP_HOST"] = @previous_host
  end

  test "an admin sends a provider's changes to the connection's address and saves its secret, and the map says live updates are on" do
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => @row.integration_id)

    assert_text "Live updates: off"
    assert_text "Send Northflank's changes to Firefight and save the signing secret under Integrations to turn them on."
    assert_text "/api/v1/map_events/#{@row.map_events_token}"
    assert_text LiveTestEvents.setup_steps.first
    page.scroll_to(find("#map-events-secret-#{@row.id}"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-setup.png"))

    fill_in "map-events-secret-#{@row.id}", with: "whsec"
    click_button "Save secret"

    assert_text "Signing secret saved. Changes Northflank sends now reach the map."
    assert_text "Live updates: on, no change received yet"
    assert_equal "whsec", @row.reload.map_events_secret
    page.scroll_to(find("#map-events-secret-#{@row.id}"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-saved.png"))

    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ LiveTestPack.found(ResourceMap::KIND_SERVICE, "web") ]))
    @row.update!(map_events_received_at: 3.minutes.ago)
    visit resource_map_path

    within("aside[aria-label='What needs attention']") do
      assert_text "Live updates"
      assert_text "Live updates: on, last event 3 minutes ago"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-map.png"))
  end
end
