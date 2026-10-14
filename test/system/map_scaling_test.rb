require "application_system_test_case"

class MapScalingTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    row = integration.integration_environments.create!(credentials: { token: "x" }.to_json)
    web = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web",
                                 url: "https://app.northflank.com/s/acme/shop/services/web")
    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ web.with(details: { ResourceMap::INSTANCES => 2 }) ]), at: 2.hours.ago)
    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ web.with(details: { ResourceMap::INSTANCES => 6 }) ]), at: 30.minutes.ago)
    @web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
  end

  test "a service's panel shows how many instances it runs and when it scaled" do
    visit resource_map_path(ResourceMap::PAGE_VIEW_PARAM => "focus", ResourceMap::PAGE_RESOURCE_PARAM => @web.id)

    within("aside[aria-label='About web']") do
      assert_text "Instances\n6"
      assert_text "web went from 2 to 6 instances"
    end
    take_screenshot
  end
end
